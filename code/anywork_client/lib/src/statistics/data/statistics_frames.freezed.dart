// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'statistics_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PerformanceSummariesFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $PerformanceSummariesFrameCopyWith<$Res>  {
$PerformanceSummariesFrameCopyWith(PerformanceSummariesFrame _, $Res Function(PerformanceSummariesFrame) __);
}


/// Adds pattern-matching-related methods to [PerformanceSummariesFrame].
extension PerformanceSummariesFramePatterns on PerformanceSummariesFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PerformanceSummariesData value)?  data,TResult Function( PerformanceSummariesResyncRequired value)?  resyncRequired,TResult Function( PerformanceSummariesFeedFailure value)?  failure,TResult Function( PerformanceSummariesClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PerformanceSummariesData() when data != null:
return data(_that);case PerformanceSummariesResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case PerformanceSummariesFeedFailure() when failure != null:
return failure(_that);case PerformanceSummariesClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PerformanceSummariesData value)  data,required TResult Function( PerformanceSummariesResyncRequired value)  resyncRequired,required TResult Function( PerformanceSummariesFeedFailure value)  failure,required TResult Function( PerformanceSummariesClosed value)  closed,}){
final _that = this;
switch (_that) {
case PerformanceSummariesData():
return data(_that);case PerformanceSummariesResyncRequired():
return resyncRequired(_that);case PerformanceSummariesFeedFailure():
return failure(_that);case PerformanceSummariesClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PerformanceSummariesData value)?  data,TResult? Function( PerformanceSummariesResyncRequired value)?  resyncRequired,TResult? Function( PerformanceSummariesFeedFailure value)?  failure,TResult? Function( PerformanceSummariesClosed value)?  closed,}){
final _that = this;
switch (_that) {
case PerformanceSummariesData() when data != null:
return data(_that);case PerformanceSummariesResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case PerformanceSummariesFeedFailure() when failure != null:
return failure(_that);case PerformanceSummariesClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  PerformanceSummariesEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PerformanceSummariesData() when data != null:
return data(_that.deliverySequence,_that.event);case PerformanceSummariesResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case PerformanceSummariesFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case PerformanceSummariesClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  PerformanceSummariesEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case PerformanceSummariesData():
return data(_that.deliverySequence,_that.event);case PerformanceSummariesResyncRequired():
return resyncRequired(_that.identity,_that.reason);case PerformanceSummariesFeedFailure():
return failure(_that.identity,_that.error);case PerformanceSummariesClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  PerformanceSummariesEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case PerformanceSummariesData() when data != null:
return data(_that.deliverySequence,_that.event);case PerformanceSummariesResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case PerformanceSummariesFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case PerformanceSummariesClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class PerformanceSummariesData implements PerformanceSummariesFrame {
  const PerformanceSummariesData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  PerformanceSummariesEvent event;

/// Create a copy of PerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesDataCopyWith<PerformanceSummariesData> get copyWith => _$PerformanceSummariesDataCopyWithImpl<PerformanceSummariesData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $PerformanceSummariesDataCopyWith<$Res> implements $PerformanceSummariesFrameCopyWith<$Res> {
  factory $PerformanceSummariesDataCopyWith(PerformanceSummariesData value, $Res Function(PerformanceSummariesData) _then) = _$PerformanceSummariesDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, PerformanceSummariesEvent event
});


$PerformanceSummariesEventCopyWith<$Res> get event;

}
/// @nodoc
class _$PerformanceSummariesDataCopyWithImpl<$Res>
    implements $PerformanceSummariesDataCopyWith<$Res> {
  _$PerformanceSummariesDataCopyWithImpl(this._self, this._then);

  final PerformanceSummariesData _self;
  final $Res Function(PerformanceSummariesData) _then;

/// Create a copy of PerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(PerformanceSummariesData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesEvent,
  ));
}

/// Create a copy of PerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesEventCopyWith<$Res> get event {

  return $PerformanceSummariesEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class PerformanceSummariesResyncRequired implements PerformanceSummariesFrame {
  const PerformanceSummariesResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of PerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesResyncRequiredCopyWith<PerformanceSummariesResyncRequired> get copyWith => _$PerformanceSummariesResyncRequiredCopyWithImpl<PerformanceSummariesResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $PerformanceSummariesResyncRequiredCopyWith<$Res> implements $PerformanceSummariesFrameCopyWith<$Res> {
  factory $PerformanceSummariesResyncRequiredCopyWith(PerformanceSummariesResyncRequired value, $Res Function(PerformanceSummariesResyncRequired) _then) = _$PerformanceSummariesResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$PerformanceSummariesResyncRequiredCopyWithImpl<$Res>
    implements $PerformanceSummariesResyncRequiredCopyWith<$Res> {
  _$PerformanceSummariesResyncRequiredCopyWithImpl(this._self, this._then);

  final PerformanceSummariesResyncRequired _self;
  final $Res Function(PerformanceSummariesResyncRequired) _then;

/// Create a copy of PerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(PerformanceSummariesResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of PerformanceSummariesFrame
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


class PerformanceSummariesFeedFailure implements PerformanceSummariesFrame {
  const PerformanceSummariesFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of PerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesFeedFailureCopyWith<PerformanceSummariesFeedFailure> get copyWith => _$PerformanceSummariesFeedFailureCopyWithImpl<PerformanceSummariesFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $PerformanceSummariesFeedFailureCopyWith<$Res> implements $PerformanceSummariesFrameCopyWith<$Res> {
  factory $PerformanceSummariesFeedFailureCopyWith(PerformanceSummariesFeedFailure value, $Res Function(PerformanceSummariesFeedFailure) _then) = _$PerformanceSummariesFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$PerformanceSummariesFeedFailureCopyWithImpl<$Res>
    implements $PerformanceSummariesFeedFailureCopyWith<$Res> {
  _$PerformanceSummariesFeedFailureCopyWithImpl(this._self, this._then);

  final PerformanceSummariesFeedFailure _self;
  final $Res Function(PerformanceSummariesFeedFailure) _then;

/// Create a copy of PerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(PerformanceSummariesFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of PerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceSummariesFrame
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


class PerformanceSummariesClosed implements PerformanceSummariesFrame {
  const PerformanceSummariesClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of PerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesClosedCopyWith<PerformanceSummariesClosed> get copyWith => _$PerformanceSummariesClosedCopyWithImpl<PerformanceSummariesClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $PerformanceSummariesClosedCopyWith<$Res> implements $PerformanceSummariesFrameCopyWith<$Res> {
  factory $PerformanceSummariesClosedCopyWith(PerformanceSummariesClosed value, $Res Function(PerformanceSummariesClosed) _then) = _$PerformanceSummariesClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$PerformanceSummariesClosedCopyWithImpl<$Res>
    implements $PerformanceSummariesClosedCopyWith<$Res> {
  _$PerformanceSummariesClosedCopyWithImpl(this._self, this._then);

  final PerformanceSummariesClosed _self;
  final $Res Function(PerformanceSummariesClosed) _then;

/// Create a copy of PerformanceSummariesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(PerformanceSummariesClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of PerformanceSummariesFrame
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
mixin _$PerformanceSummariesEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesEventCopyWith<PerformanceSummariesEvent> get copyWith => _$PerformanceSummariesEventCopyWithImpl<PerformanceSummariesEvent>(this as PerformanceSummariesEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummariesEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as PerformanceSummariesEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}



}

/// @nodoc
abstract mixin class $PerformanceSummariesEventCopyWith<$Res>  {
  factory $PerformanceSummariesEventCopyWith(PerformanceSummariesEvent value, $Res Function(PerformanceSummariesEvent) _then) = _$PerformanceSummariesEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$PerformanceSummariesEventCopyWithImpl<$Res>
    implements $PerformanceSummariesEventCopyWith<$Res> {
  _$PerformanceSummariesEventCopyWithImpl(this._self, this._then);

  final PerformanceSummariesEvent _self;
  final $Res Function(PerformanceSummariesEvent) _then;

/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSummariesEvent].
extension PerformanceSummariesEventPatterns on PerformanceSummariesEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PerformanceSummariesBaselineEvent value)?  baseline,TResult Function( PerformanceSummariesChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PerformanceSummariesBaselineEvent() when baseline != null:
return baseline(_that);case PerformanceSummariesChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PerformanceSummariesBaselineEvent value)  baseline,required TResult Function( PerformanceSummariesChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case PerformanceSummariesBaselineEvent():
return baseline(_that);case PerformanceSummariesChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PerformanceSummariesBaselineEvent value)?  baseline,TResult? Function( PerformanceSummariesChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case PerformanceSummariesBaselineEvent() when baseline != null:
return baseline(_that);case PerformanceSummariesChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PerformanceSummariesBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  PerformanceSummariesChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PerformanceSummariesBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case PerformanceSummariesChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PerformanceSummariesBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  PerformanceSummariesChange value)  change,}) {final _that = this;
switch (_that) {
case PerformanceSummariesBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case PerformanceSummariesChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PerformanceSummariesBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  PerformanceSummariesChange value)?  change,}) {final _that = this;
switch (_that) {
case PerformanceSummariesBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case PerformanceSummariesChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class PerformanceSummariesBaselineEvent implements PerformanceSummariesEvent {
  const PerformanceSummariesBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  PerformanceSummariesBaseline value;

/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesBaselineEventCopyWith<PerformanceSummariesBaselineEvent> get copyWith => _$PerformanceSummariesBaselineEventCopyWithImpl<PerformanceSummariesBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $PerformanceSummariesBaselineEventCopyWith<$Res> implements $PerformanceSummariesEventCopyWith<$Res> {
  factory $PerformanceSummariesBaselineEventCopyWith(PerformanceSummariesBaselineEvent value, $Res Function(PerformanceSummariesBaselineEvent) _then) = _$PerformanceSummariesBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, PerformanceSummariesBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$PerformanceSummariesBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$PerformanceSummariesBaselineEventCopyWithImpl<$Res>
    implements $PerformanceSummariesBaselineEventCopyWith<$Res> {
  _$PerformanceSummariesBaselineEventCopyWithImpl(this._self, this._then);

  final PerformanceSummariesBaselineEvent _self;
  final $Res Function(PerformanceSummariesBaselineEvent) _then;

/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(PerformanceSummariesBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesBaseline,
  ));
}

/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesBaselineCopyWith<$Res> get value {

  return $PerformanceSummariesBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class PerformanceSummariesChangeEvent implements PerformanceSummariesEvent {
  const PerformanceSummariesChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  PerformanceSummariesChange value;

/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesChangeEventCopyWith<PerformanceSummariesChangeEvent> get copyWith => _$PerformanceSummariesChangeEventCopyWithImpl<PerformanceSummariesChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}



}

/// @nodoc
abstract mixin class $PerformanceSummariesChangeEventCopyWith<$Res> implements $PerformanceSummariesEventCopyWith<$Res> {
  factory $PerformanceSummariesChangeEventCopyWith(PerformanceSummariesChangeEvent value, $Res Function(PerformanceSummariesChangeEvent) _then) = _$PerformanceSummariesChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, PerformanceSummariesChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$PerformanceSummariesChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$PerformanceSummariesChangeEventCopyWithImpl<$Res>
    implements $PerformanceSummariesChangeEventCopyWith<$Res> {
  _$PerformanceSummariesChangeEventCopyWithImpl(this._self, this._then);

  final PerformanceSummariesChangeEvent _self;
  final $Res Function(PerformanceSummariesChangeEvent) _then;

/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(PerformanceSummariesChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesChange,
  ));
}

/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of PerformanceSummariesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesChangeCopyWith<$Res> get value {

  return $PerformanceSummariesChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$PerformanceSummariesBaseline {

 PerformanceSummariesHeader get header; ProductCollectionRef? get collection;
/// Create a copy of PerformanceSummariesBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesBaselineCopyWith<PerformanceSummariesBaseline> get copyWith => _$PerformanceSummariesBaselineCopyWithImpl<PerformanceSummariesBaseline>(this as PerformanceSummariesBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummariesBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as PerformanceSummariesBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}



}

/// @nodoc
abstract mixin class $PerformanceSummariesBaselineCopyWith<$Res>  {
  factory $PerformanceSummariesBaselineCopyWith(PerformanceSummariesBaseline value, $Res Function(PerformanceSummariesBaseline) _then) = _$PerformanceSummariesBaselineCopyWithImpl;
@useResult
$Res call({
 PerformanceSummariesHeader header, ProductCollectionRef? collection
});


$PerformanceSummariesHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$PerformanceSummariesBaselineCopyWithImpl<$Res>
    implements $PerformanceSummariesBaselineCopyWith<$Res> {
  _$PerformanceSummariesBaselineCopyWithImpl(this._self, this._then);

  final PerformanceSummariesBaseline _self;
  final $Res Function(PerformanceSummariesBaseline) _then;

/// Create a copy of PerformanceSummariesBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(PerformanceSummariesBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of PerformanceSummariesBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesHeaderCopyWith<$Res> get header {

  return $PerformanceSummariesHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of PerformanceSummariesBaseline
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


/// Adds pattern-matching-related methods to [PerformanceSummariesBaseline].
extension PerformanceSummariesBaselinePatterns on PerformanceSummariesBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummariesBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummariesBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummariesBaseline value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummariesBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PerformanceSummariesHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummariesBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PerformanceSummariesHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PerformanceSummariesHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummariesBaseline implements PerformanceSummariesBaseline {
  const _PerformanceSummariesBaseline({required this.header, required this.collection});


@override final  PerformanceSummariesHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of PerformanceSummariesBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummariesBaselineCopyWith<_PerformanceSummariesBaseline> get copyWith => __$PerformanceSummariesBaselineCopyWithImpl<_PerformanceSummariesBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummariesBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}



}

/// @nodoc
abstract mixin class _$PerformanceSummariesBaselineCopyWith<$Res> implements $PerformanceSummariesBaselineCopyWith<$Res> {
  factory _$PerformanceSummariesBaselineCopyWith(_PerformanceSummariesBaseline value, $Res Function(_PerformanceSummariesBaseline) _then) = __$PerformanceSummariesBaselineCopyWithImpl;
@override @useResult
$Res call({
 PerformanceSummariesHeader header, ProductCollectionRef? collection
});


@override $PerformanceSummariesHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$PerformanceSummariesBaselineCopyWithImpl<$Res>
    implements _$PerformanceSummariesBaselineCopyWith<$Res> {
  __$PerformanceSummariesBaselineCopyWithImpl(this._self, this._then);

  final _PerformanceSummariesBaseline _self;
  final $Res Function(_PerformanceSummariesBaseline) _then;

/// Create a copy of PerformanceSummariesBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_PerformanceSummariesBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of PerformanceSummariesBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesHeaderCopyWith<$Res> get header {

  return $PerformanceSummariesHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of PerformanceSummariesBaseline
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
mixin _$PerformanceSummariesChange {

 PerformanceSummariesHeader get header; int? get baseCollectionRevision; ProductCollectionRef? get collection; List<ProductEntityRef> get upserted; List<int> get removedEntries;
/// Create a copy of PerformanceSummariesChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesChangeCopyWith<PerformanceSummariesChange> get copyWith => _$PerformanceSummariesChangeCopyWithImpl<PerformanceSummariesChange>(this as PerformanceSummariesChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummariesChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as PerformanceSummariesChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $PerformanceSummariesChangeCopyWith<$Res>  {
  factory $PerformanceSummariesChangeCopyWith(PerformanceSummariesChange value, $Res Function(PerformanceSummariesChange) _then) = _$PerformanceSummariesChangeCopyWithImpl;
@useResult
$Res call({
 PerformanceSummariesHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$PerformanceSummariesHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$PerformanceSummariesChangeCopyWithImpl<$Res>
    implements $PerformanceSummariesChangeCopyWith<$Res> {
  _$PerformanceSummariesChangeCopyWithImpl(this._self, this._then);

  final PerformanceSummariesChange _self;
  final $Res Function(PerformanceSummariesChange) _then;

/// Create a copy of PerformanceSummariesChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(PerformanceSummariesChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of PerformanceSummariesChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesHeaderCopyWith<$Res> get header {

  return $PerformanceSummariesHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of PerformanceSummariesChange
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


/// Adds pattern-matching-related methods to [PerformanceSummariesChange].
extension PerformanceSummariesChangePatterns on PerformanceSummariesChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummariesChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummariesChange() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummariesChange value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesChange():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummariesChange value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesChange() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PerformanceSummariesHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummariesChange() when $default != null:
return $default(_that.header,_that.baseCollectionRevision,_that.collection,_that.upserted,_that.removedEntries);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PerformanceSummariesHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesChange():
return $default(_that.header,_that.baseCollectionRevision,_that.collection,_that.upserted,_that.removedEntries);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PerformanceSummariesHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesChange() when $default != null:
return $default(_that.header,_that.baseCollectionRevision,_that.collection,_that.upserted,_that.removedEntries);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummariesChange implements PerformanceSummariesChange {
  const _PerformanceSummariesChange({required this.header, required this.baseCollectionRevision, required this.collection, required  List<ProductEntityRef> upserted, required  List<int> removedEntries}): _upserted = upserted,_removedEntries = removedEntries;


@override final  PerformanceSummariesHeader header;
@override final  int? baseCollectionRevision;
@override final  ProductCollectionRef? collection;
 final  List<ProductEntityRef> _upserted;
@override List<ProductEntityRef> get upserted {
  if (_upserted is EqualUnmodifiableListView) return _upserted;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_upserted);
}

 final  List<int> _removedEntries;
@override List<int> get removedEntries {
  if (_removedEntries is EqualUnmodifiableListView) return _removedEntries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_removedEntries);
}


/// Create a copy of PerformanceSummariesChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummariesChangeCopyWith<_PerformanceSummariesChange> get copyWith => __$PerformanceSummariesChangeCopyWithImpl<_PerformanceSummariesChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummariesChange&&(identical(other.header, header) || other.header == header)&&(identical(other.baseCollectionRevision, baseCollectionRevision) || other.baseCollectionRevision == baseCollectionRevision)&&(identical(other.collection, collection) || other.collection == collection)&&const DeepCollectionEquality().equals(other.upserted, _upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _removedEntries));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,baseCollectionRevision,collection,const DeepCollectionEquality().hash(_upserted),const DeepCollectionEquality().hash(_removedEntries));
}



}

/// @nodoc
abstract mixin class _$PerformanceSummariesChangeCopyWith<$Res> implements $PerformanceSummariesChangeCopyWith<$Res> {
  factory _$PerformanceSummariesChangeCopyWith(_PerformanceSummariesChange value, $Res Function(_PerformanceSummariesChange) _then) = __$PerformanceSummariesChangeCopyWithImpl;
@override @useResult
$Res call({
 PerformanceSummariesHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


@override $PerformanceSummariesHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$PerformanceSummariesChangeCopyWithImpl<$Res>
    implements _$PerformanceSummariesChangeCopyWith<$Res> {
  __$PerformanceSummariesChangeCopyWithImpl(this._self, this._then);

  final _PerformanceSummariesChange _self;
  final $Res Function(_PerformanceSummariesChange) _then;

/// Create a copy of PerformanceSummariesChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(_PerformanceSummariesChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self._upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self._removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}

/// Create a copy of PerformanceSummariesChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesHeaderCopyWith<$Res> get header {

  return $PerformanceSummariesHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of PerformanceSummariesChange
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
mixin _$PerformanceHistoryFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $PerformanceHistoryFrameCopyWith<$Res>  {
$PerformanceHistoryFrameCopyWith(PerformanceHistoryFrame _, $Res Function(PerformanceHistoryFrame) __);
}


/// Adds pattern-matching-related methods to [PerformanceHistoryFrame].
extension PerformanceHistoryFramePatterns on PerformanceHistoryFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PerformanceHistoryData value)?  data,TResult Function( PerformanceHistoryResyncRequired value)?  resyncRequired,TResult Function( PerformanceHistoryFeedFailure value)?  failure,TResult Function( PerformanceHistoryClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PerformanceHistoryData() when data != null:
return data(_that);case PerformanceHistoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case PerformanceHistoryFeedFailure() when failure != null:
return failure(_that);case PerformanceHistoryClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PerformanceHistoryData value)  data,required TResult Function( PerformanceHistoryResyncRequired value)  resyncRequired,required TResult Function( PerformanceHistoryFeedFailure value)  failure,required TResult Function( PerformanceHistoryClosed value)  closed,}){
final _that = this;
switch (_that) {
case PerformanceHistoryData():
return data(_that);case PerformanceHistoryResyncRequired():
return resyncRequired(_that);case PerformanceHistoryFeedFailure():
return failure(_that);case PerformanceHistoryClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PerformanceHistoryData value)?  data,TResult? Function( PerformanceHistoryResyncRequired value)?  resyncRequired,TResult? Function( PerformanceHistoryFeedFailure value)?  failure,TResult? Function( PerformanceHistoryClosed value)?  closed,}){
final _that = this;
switch (_that) {
case PerformanceHistoryData() when data != null:
return data(_that);case PerformanceHistoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case PerformanceHistoryFeedFailure() when failure != null:
return failure(_that);case PerformanceHistoryClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  PerformanceHistoryEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PerformanceHistoryData() when data != null:
return data(_that.deliverySequence,_that.event);case PerformanceHistoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case PerformanceHistoryFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case PerformanceHistoryClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  PerformanceHistoryEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case PerformanceHistoryData():
return data(_that.deliverySequence,_that.event);case PerformanceHistoryResyncRequired():
return resyncRequired(_that.identity,_that.reason);case PerformanceHistoryFeedFailure():
return failure(_that.identity,_that.error);case PerformanceHistoryClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  PerformanceHistoryEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case PerformanceHistoryData() when data != null:
return data(_that.deliverySequence,_that.event);case PerformanceHistoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case PerformanceHistoryFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case PerformanceHistoryClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class PerformanceHistoryData implements PerformanceHistoryFrame {
  const PerformanceHistoryData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  PerformanceHistoryEvent event;

/// Create a copy of PerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryDataCopyWith<PerformanceHistoryData> get copyWith => _$PerformanceHistoryDataCopyWithImpl<PerformanceHistoryData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $PerformanceHistoryDataCopyWith<$Res> implements $PerformanceHistoryFrameCopyWith<$Res> {
  factory $PerformanceHistoryDataCopyWith(PerformanceHistoryData value, $Res Function(PerformanceHistoryData) _then) = _$PerformanceHistoryDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, PerformanceHistoryEvent event
});


$PerformanceHistoryEventCopyWith<$Res> get event;

}
/// @nodoc
class _$PerformanceHistoryDataCopyWithImpl<$Res>
    implements $PerformanceHistoryDataCopyWith<$Res> {
  _$PerformanceHistoryDataCopyWithImpl(this._self, this._then);

  final PerformanceHistoryData _self;
  final $Res Function(PerformanceHistoryData) _then;

/// Create a copy of PerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(PerformanceHistoryData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryEvent,
  ));
}

/// Create a copy of PerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryEventCopyWith<$Res> get event {

  return $PerformanceHistoryEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class PerformanceHistoryResyncRequired implements PerformanceHistoryFrame {
  const PerformanceHistoryResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of PerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryResyncRequiredCopyWith<PerformanceHistoryResyncRequired> get copyWith => _$PerformanceHistoryResyncRequiredCopyWithImpl<PerformanceHistoryResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $PerformanceHistoryResyncRequiredCopyWith<$Res> implements $PerformanceHistoryFrameCopyWith<$Res> {
  factory $PerformanceHistoryResyncRequiredCopyWith(PerformanceHistoryResyncRequired value, $Res Function(PerformanceHistoryResyncRequired) _then) = _$PerformanceHistoryResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$PerformanceHistoryResyncRequiredCopyWithImpl<$Res>
    implements $PerformanceHistoryResyncRequiredCopyWith<$Res> {
  _$PerformanceHistoryResyncRequiredCopyWithImpl(this._self, this._then);

  final PerformanceHistoryResyncRequired _self;
  final $Res Function(PerformanceHistoryResyncRequired) _then;

/// Create a copy of PerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(PerformanceHistoryResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of PerformanceHistoryFrame
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


class PerformanceHistoryFeedFailure implements PerformanceHistoryFrame {
  const PerformanceHistoryFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of PerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryFeedFailureCopyWith<PerformanceHistoryFeedFailure> get copyWith => _$PerformanceHistoryFeedFailureCopyWithImpl<PerformanceHistoryFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $PerformanceHistoryFeedFailureCopyWith<$Res> implements $PerformanceHistoryFrameCopyWith<$Res> {
  factory $PerformanceHistoryFeedFailureCopyWith(PerformanceHistoryFeedFailure value, $Res Function(PerformanceHistoryFeedFailure) _then) = _$PerformanceHistoryFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$PerformanceHistoryFeedFailureCopyWithImpl<$Res>
    implements $PerformanceHistoryFeedFailureCopyWith<$Res> {
  _$PerformanceHistoryFeedFailureCopyWithImpl(this._self, this._then);

  final PerformanceHistoryFeedFailure _self;
  final $Res Function(PerformanceHistoryFeedFailure) _then;

/// Create a copy of PerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(PerformanceHistoryFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of PerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceHistoryFrame
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


class PerformanceHistoryClosed implements PerformanceHistoryFrame {
  const PerformanceHistoryClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of PerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryClosedCopyWith<PerformanceHistoryClosed> get copyWith => _$PerformanceHistoryClosedCopyWithImpl<PerformanceHistoryClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $PerformanceHistoryClosedCopyWith<$Res> implements $PerformanceHistoryFrameCopyWith<$Res> {
  factory $PerformanceHistoryClosedCopyWith(PerformanceHistoryClosed value, $Res Function(PerformanceHistoryClosed) _then) = _$PerformanceHistoryClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$PerformanceHistoryClosedCopyWithImpl<$Res>
    implements $PerformanceHistoryClosedCopyWith<$Res> {
  _$PerformanceHistoryClosedCopyWithImpl(this._self, this._then);

  final PerformanceHistoryClosed _self;
  final $Res Function(PerformanceHistoryClosed) _then;

/// Create a copy of PerformanceHistoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(PerformanceHistoryClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of PerformanceHistoryFrame
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
mixin _$PerformanceHistoryEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryEventCopyWith<PerformanceHistoryEvent> get copyWith => _$PerformanceHistoryEventCopyWithImpl<PerformanceHistoryEvent>(this as PerformanceHistoryEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceHistoryEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as PerformanceHistoryEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}



}

/// @nodoc
abstract mixin class $PerformanceHistoryEventCopyWith<$Res>  {
  factory $PerformanceHistoryEventCopyWith(PerformanceHistoryEvent value, $Res Function(PerformanceHistoryEvent) _then) = _$PerformanceHistoryEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$PerformanceHistoryEventCopyWithImpl<$Res>
    implements $PerformanceHistoryEventCopyWith<$Res> {
  _$PerformanceHistoryEventCopyWithImpl(this._self, this._then);

  final PerformanceHistoryEvent _self;
  final $Res Function(PerformanceHistoryEvent) _then;

/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceHistoryEvent].
extension PerformanceHistoryEventPatterns on PerformanceHistoryEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PerformanceHistoryBaselineEvent value)?  baseline,TResult Function( PerformanceHistoryChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PerformanceHistoryBaselineEvent() when baseline != null:
return baseline(_that);case PerformanceHistoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PerformanceHistoryBaselineEvent value)  baseline,required TResult Function( PerformanceHistoryChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case PerformanceHistoryBaselineEvent():
return baseline(_that);case PerformanceHistoryChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PerformanceHistoryBaselineEvent value)?  baseline,TResult? Function( PerformanceHistoryChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case PerformanceHistoryBaselineEvent() when baseline != null:
return baseline(_that);case PerformanceHistoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PerformanceHistoryBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  PerformanceHistoryChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PerformanceHistoryBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case PerformanceHistoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PerformanceHistoryBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  PerformanceHistoryChange value)  change,}) {final _that = this;
switch (_that) {
case PerformanceHistoryBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case PerformanceHistoryChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PerformanceHistoryBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  PerformanceHistoryChange value)?  change,}) {final _that = this;
switch (_that) {
case PerformanceHistoryBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case PerformanceHistoryChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class PerformanceHistoryBaselineEvent implements PerformanceHistoryEvent {
  const PerformanceHistoryBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  PerformanceHistoryBaseline value;

/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryBaselineEventCopyWith<PerformanceHistoryBaselineEvent> get copyWith => _$PerformanceHistoryBaselineEventCopyWithImpl<PerformanceHistoryBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $PerformanceHistoryBaselineEventCopyWith<$Res> implements $PerformanceHistoryEventCopyWith<$Res> {
  factory $PerformanceHistoryBaselineEventCopyWith(PerformanceHistoryBaselineEvent value, $Res Function(PerformanceHistoryBaselineEvent) _then) = _$PerformanceHistoryBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, PerformanceHistoryBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$PerformanceHistoryBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$PerformanceHistoryBaselineEventCopyWithImpl<$Res>
    implements $PerformanceHistoryBaselineEventCopyWith<$Res> {
  _$PerformanceHistoryBaselineEventCopyWithImpl(this._self, this._then);

  final PerformanceHistoryBaselineEvent _self;
  final $Res Function(PerformanceHistoryBaselineEvent) _then;

/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(PerformanceHistoryBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryBaseline,
  ));
}

/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryBaselineCopyWith<$Res> get value {

  return $PerformanceHistoryBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class PerformanceHistoryChangeEvent implements PerformanceHistoryEvent {
  const PerformanceHistoryChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  PerformanceHistoryChange value;

/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryChangeEventCopyWith<PerformanceHistoryChangeEvent> get copyWith => _$PerformanceHistoryChangeEventCopyWithImpl<PerformanceHistoryChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}



}

/// @nodoc
abstract mixin class $PerformanceHistoryChangeEventCopyWith<$Res> implements $PerformanceHistoryEventCopyWith<$Res> {
  factory $PerformanceHistoryChangeEventCopyWith(PerformanceHistoryChangeEvent value, $Res Function(PerformanceHistoryChangeEvent) _then) = _$PerformanceHistoryChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, PerformanceHistoryChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$PerformanceHistoryChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$PerformanceHistoryChangeEventCopyWithImpl<$Res>
    implements $PerformanceHistoryChangeEventCopyWith<$Res> {
  _$PerformanceHistoryChangeEventCopyWithImpl(this._self, this._then);

  final PerformanceHistoryChangeEvent _self;
  final $Res Function(PerformanceHistoryChangeEvent) _then;

/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(PerformanceHistoryChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryChange,
  ));
}

/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of PerformanceHistoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryChangeCopyWith<$Res> get value {

  return $PerformanceHistoryChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$PerformanceHistoryBaseline {

 PerformanceHistoryHeader get header; ProductCollectionRef? get collection;
/// Create a copy of PerformanceHistoryBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryBaselineCopyWith<PerformanceHistoryBaseline> get copyWith => _$PerformanceHistoryBaselineCopyWithImpl<PerformanceHistoryBaseline>(this as PerformanceHistoryBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceHistoryBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as PerformanceHistoryBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}



}

/// @nodoc
abstract mixin class $PerformanceHistoryBaselineCopyWith<$Res>  {
  factory $PerformanceHistoryBaselineCopyWith(PerformanceHistoryBaseline value, $Res Function(PerformanceHistoryBaseline) _then) = _$PerformanceHistoryBaselineCopyWithImpl;
@useResult
$Res call({
 PerformanceHistoryHeader header, ProductCollectionRef? collection
});


$PerformanceHistoryHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$PerformanceHistoryBaselineCopyWithImpl<$Res>
    implements $PerformanceHistoryBaselineCopyWith<$Res> {
  _$PerformanceHistoryBaselineCopyWithImpl(this._self, this._then);

  final PerformanceHistoryBaseline _self;
  final $Res Function(PerformanceHistoryBaseline) _then;

/// Create a copy of PerformanceHistoryBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(PerformanceHistoryBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of PerformanceHistoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryHeaderCopyWith<$Res> get header {

  return $PerformanceHistoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of PerformanceHistoryBaseline
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


/// Adds pattern-matching-related methods to [PerformanceHistoryBaseline].
extension PerformanceHistoryBaselinePatterns on PerformanceHistoryBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceHistoryBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceHistoryBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceHistoryBaseline value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceHistoryBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PerformanceHistoryHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceHistoryBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PerformanceHistoryHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PerformanceHistoryHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceHistoryBaseline implements PerformanceHistoryBaseline {
  const _PerformanceHistoryBaseline({required this.header, required this.collection});


@override final  PerformanceHistoryHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of PerformanceHistoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceHistoryBaselineCopyWith<_PerformanceHistoryBaseline> get copyWith => __$PerformanceHistoryBaselineCopyWithImpl<_PerformanceHistoryBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceHistoryBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}



}

/// @nodoc
abstract mixin class _$PerformanceHistoryBaselineCopyWith<$Res> implements $PerformanceHistoryBaselineCopyWith<$Res> {
  factory _$PerformanceHistoryBaselineCopyWith(_PerformanceHistoryBaseline value, $Res Function(_PerformanceHistoryBaseline) _then) = __$PerformanceHistoryBaselineCopyWithImpl;
@override @useResult
$Res call({
 PerformanceHistoryHeader header, ProductCollectionRef? collection
});


@override $PerformanceHistoryHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$PerformanceHistoryBaselineCopyWithImpl<$Res>
    implements _$PerformanceHistoryBaselineCopyWith<$Res> {
  __$PerformanceHistoryBaselineCopyWithImpl(this._self, this._then);

  final _PerformanceHistoryBaseline _self;
  final $Res Function(_PerformanceHistoryBaseline) _then;

/// Create a copy of PerformanceHistoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_PerformanceHistoryBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of PerformanceHistoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryHeaderCopyWith<$Res> get header {

  return $PerformanceHistoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of PerformanceHistoryBaseline
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
mixin _$PerformanceHistoryChange {

 PerformanceHistoryHeader get header; int? get baseCollectionRevision; ProductCollectionRef? get collection; List<ProductEntityRef> get upserted; List<int> get removedEntries;
/// Create a copy of PerformanceHistoryChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryChangeCopyWith<PerformanceHistoryChange> get copyWith => _$PerformanceHistoryChangeCopyWithImpl<PerformanceHistoryChange>(this as PerformanceHistoryChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceHistoryChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as PerformanceHistoryChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $PerformanceHistoryChangeCopyWith<$Res>  {
  factory $PerformanceHistoryChangeCopyWith(PerformanceHistoryChange value, $Res Function(PerformanceHistoryChange) _then) = _$PerformanceHistoryChangeCopyWithImpl;
@useResult
$Res call({
 PerformanceHistoryHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$PerformanceHistoryHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$PerformanceHistoryChangeCopyWithImpl<$Res>
    implements $PerformanceHistoryChangeCopyWith<$Res> {
  _$PerformanceHistoryChangeCopyWithImpl(this._self, this._then);

  final PerformanceHistoryChange _self;
  final $Res Function(PerformanceHistoryChange) _then;

/// Create a copy of PerformanceHistoryChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(PerformanceHistoryChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of PerformanceHistoryChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryHeaderCopyWith<$Res> get header {

  return $PerformanceHistoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of PerformanceHistoryChange
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


/// Adds pattern-matching-related methods to [PerformanceHistoryChange].
extension PerformanceHistoryChangePatterns on PerformanceHistoryChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceHistoryChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceHistoryChange() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceHistoryChange value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryChange():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceHistoryChange value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryChange() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PerformanceHistoryHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceHistoryChange() when $default != null:
return $default(_that.header,_that.baseCollectionRevision,_that.collection,_that.upserted,_that.removedEntries);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PerformanceHistoryHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryChange():
return $default(_that.header,_that.baseCollectionRevision,_that.collection,_that.upserted,_that.removedEntries);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PerformanceHistoryHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryChange() when $default != null:
return $default(_that.header,_that.baseCollectionRevision,_that.collection,_that.upserted,_that.removedEntries);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceHistoryChange implements PerformanceHistoryChange {
  const _PerformanceHistoryChange({required this.header, required this.baseCollectionRevision, required this.collection, required  List<ProductEntityRef> upserted, required  List<int> removedEntries}): _upserted = upserted,_removedEntries = removedEntries;


@override final  PerformanceHistoryHeader header;
@override final  int? baseCollectionRevision;
@override final  ProductCollectionRef? collection;
 final  List<ProductEntityRef> _upserted;
@override List<ProductEntityRef> get upserted {
  if (_upserted is EqualUnmodifiableListView) return _upserted;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_upserted);
}

 final  List<int> _removedEntries;
@override List<int> get removedEntries {
  if (_removedEntries is EqualUnmodifiableListView) return _removedEntries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_removedEntries);
}


/// Create a copy of PerformanceHistoryChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceHistoryChangeCopyWith<_PerformanceHistoryChange> get copyWith => __$PerformanceHistoryChangeCopyWithImpl<_PerformanceHistoryChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceHistoryChange&&(identical(other.header, header) || other.header == header)&&(identical(other.baseCollectionRevision, baseCollectionRevision) || other.baseCollectionRevision == baseCollectionRevision)&&(identical(other.collection, collection) || other.collection == collection)&&const DeepCollectionEquality().equals(other.upserted, _upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _removedEntries));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,baseCollectionRevision,collection,const DeepCollectionEquality().hash(_upserted),const DeepCollectionEquality().hash(_removedEntries));
}



}

/// @nodoc
abstract mixin class _$PerformanceHistoryChangeCopyWith<$Res> implements $PerformanceHistoryChangeCopyWith<$Res> {
  factory _$PerformanceHistoryChangeCopyWith(_PerformanceHistoryChange value, $Res Function(_PerformanceHistoryChange) _then) = __$PerformanceHistoryChangeCopyWithImpl;
@override @useResult
$Res call({
 PerformanceHistoryHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


@override $PerformanceHistoryHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$PerformanceHistoryChangeCopyWithImpl<$Res>
    implements _$PerformanceHistoryChangeCopyWith<$Res> {
  __$PerformanceHistoryChangeCopyWithImpl(this._self, this._then);

  final _PerformanceHistoryChange _self;
  final $Res Function(_PerformanceHistoryChange) _then;

/// Create a copy of PerformanceHistoryChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(_PerformanceHistoryChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self._upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self._removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}

/// Create a copy of PerformanceHistoryChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryHeaderCopyWith<$Res> get header {

  return $PerformanceHistoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of PerformanceHistoryChange
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

// dart format on
