// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'usage_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountUsageFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AccountUsageFrameCopyWith<$Res>  {
$AccountUsageFrameCopyWith(AccountUsageFrame _, $Res Function(AccountUsageFrame) __);
}


/// Adds pattern-matching-related methods to [AccountUsageFrame].
extension AccountUsageFramePatterns on AccountUsageFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AccountUsageDataFrame value)?  data,TResult Function( AccountUsageResyncRequired value)?  resyncRequired,TResult Function( AccountUsageFeedFailure value)?  failure,TResult Function( AccountUsageClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AccountUsageDataFrame() when data != null:
return data(_that);case AccountUsageResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AccountUsageFeedFailure() when failure != null:
return failure(_that);case AccountUsageClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AccountUsageDataFrame value)  data,required TResult Function( AccountUsageResyncRequired value)  resyncRequired,required TResult Function( AccountUsageFeedFailure value)  failure,required TResult Function( AccountUsageClosed value)  closed,}){
final _that = this;
switch (_that) {
case AccountUsageDataFrame():
return data(_that);case AccountUsageResyncRequired():
return resyncRequired(_that);case AccountUsageFeedFailure():
return failure(_that);case AccountUsageClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AccountUsageDataFrame value)?  data,TResult? Function( AccountUsageResyncRequired value)?  resyncRequired,TResult? Function( AccountUsageFeedFailure value)?  failure,TResult? Function( AccountUsageClosed value)?  closed,}){
final _that = this;
switch (_that) {
case AccountUsageDataFrame() when data != null:
return data(_that);case AccountUsageResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AccountUsageFeedFailure() when failure != null:
return failure(_that);case AccountUsageClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  AccountUsageEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AccountUsageDataFrame() when data != null:
return data(_that.deliverySequence,_that.event);case AccountUsageResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AccountUsageFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AccountUsageClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  AccountUsageEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case AccountUsageDataFrame():
return data(_that.deliverySequence,_that.event);case AccountUsageResyncRequired():
return resyncRequired(_that.identity,_that.reason);case AccountUsageFeedFailure():
return failure(_that.identity,_that.error);case AccountUsageClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  AccountUsageEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case AccountUsageDataFrame() when data != null:
return data(_that.deliverySequence,_that.event);case AccountUsageResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AccountUsageFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AccountUsageClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class AccountUsageDataFrame implements AccountUsageFrame {
  const AccountUsageDataFrame({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  AccountUsageEvent event;

/// Create a copy of AccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageDataFrameCopyWith<AccountUsageDataFrame> get copyWith => _$AccountUsageDataFrameCopyWithImpl<AccountUsageDataFrame>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageDataFrame&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $AccountUsageDataFrameCopyWith<$Res> implements $AccountUsageFrameCopyWith<$Res> {
  factory $AccountUsageDataFrameCopyWith(AccountUsageDataFrame value, $Res Function(AccountUsageDataFrame) _then) = _$AccountUsageDataFrameCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, AccountUsageEvent event
});


$AccountUsageEventCopyWith<$Res> get event;

}
/// @nodoc
class _$AccountUsageDataFrameCopyWithImpl<$Res>
    implements $AccountUsageDataFrameCopyWith<$Res> {
  _$AccountUsageDataFrameCopyWithImpl(this._self, this._then);

  final AccountUsageDataFrame _self;
  final $Res Function(AccountUsageDataFrame) _then;

/// Create a copy of AccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(AccountUsageDataFrame(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as AccountUsageEvent,
  ));
}

/// Create a copy of AccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageEventCopyWith<$Res> get event {

  return $AccountUsageEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class AccountUsageResyncRequired implements AccountUsageFrame {
  const AccountUsageResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of AccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageResyncRequiredCopyWith<AccountUsageResyncRequired> get copyWith => _$AccountUsageResyncRequiredCopyWithImpl<AccountUsageResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AccountUsageResyncRequiredCopyWith<$Res> implements $AccountUsageFrameCopyWith<$Res> {
  factory $AccountUsageResyncRequiredCopyWith(AccountUsageResyncRequired value, $Res Function(AccountUsageResyncRequired) _then) = _$AccountUsageResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AccountUsageResyncRequiredCopyWithImpl<$Res>
    implements $AccountUsageResyncRequiredCopyWith<$Res> {
  _$AccountUsageResyncRequiredCopyWithImpl(this._self, this._then);

  final AccountUsageResyncRequired _self;
  final $Res Function(AccountUsageResyncRequired) _then;

/// Create a copy of AccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AccountUsageResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of AccountUsageFrame
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


class AccountUsageFeedFailure implements AccountUsageFrame {
  const AccountUsageFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of AccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageFeedFailureCopyWith<AccountUsageFeedFailure> get copyWith => _$AccountUsageFeedFailureCopyWithImpl<AccountUsageFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $AccountUsageFeedFailureCopyWith<$Res> implements $AccountUsageFrameCopyWith<$Res> {
  factory $AccountUsageFeedFailureCopyWith(AccountUsageFeedFailure value, $Res Function(AccountUsageFeedFailure) _then) = _$AccountUsageFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$AccountUsageFeedFailureCopyWithImpl<$Res>
    implements $AccountUsageFeedFailureCopyWith<$Res> {
  _$AccountUsageFeedFailureCopyWithImpl(this._self, this._then);

  final AccountUsageFeedFailure _self;
  final $Res Function(AccountUsageFeedFailure) _then;

/// Create a copy of AccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(AccountUsageFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of AccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AccountUsageFrame
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


class AccountUsageClosed implements AccountUsageFrame {
  const AccountUsageClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of AccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageClosedCopyWith<AccountUsageClosed> get copyWith => _$AccountUsageClosedCopyWithImpl<AccountUsageClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AccountUsageClosedCopyWith<$Res> implements $AccountUsageFrameCopyWith<$Res> {
  factory $AccountUsageClosedCopyWith(AccountUsageClosed value, $Res Function(AccountUsageClosed) _then) = _$AccountUsageClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AccountUsageClosedCopyWithImpl<$Res>
    implements $AccountUsageClosedCopyWith<$Res> {
  _$AccountUsageClosedCopyWithImpl(this._self, this._then);

  final AccountUsageClosed _self;
  final $Res Function(AccountUsageClosed) _then;

/// Create a copy of AccountUsageFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AccountUsageClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of AccountUsageFrame
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
mixin _$AccountUsageEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageEventCopyWith<AccountUsageEvent> get copyWith => _$AccountUsageEventCopyWithImpl<AccountUsageEvent>(this as AccountUsageEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as AccountUsageEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}



}

/// @nodoc
abstract mixin class $AccountUsageEventCopyWith<$Res>  {
  factory $AccountUsageEventCopyWith(AccountUsageEvent value, $Res Function(AccountUsageEvent) _then) = _$AccountUsageEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$AccountUsageEventCopyWithImpl<$Res>
    implements $AccountUsageEventCopyWith<$Res> {
  _$AccountUsageEventCopyWithImpl(this._self, this._then);

  final AccountUsageEvent _self;
  final $Res Function(AccountUsageEvent) _then;

/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountUsageEvent].
extension AccountUsageEventPatterns on AccountUsageEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AccountUsageBaselineEvent value)?  baseline,TResult Function( AccountUsageChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AccountUsageBaselineEvent() when baseline != null:
return baseline(_that);case AccountUsageChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AccountUsageBaselineEvent value)  baseline,required TResult Function( AccountUsageChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case AccountUsageBaselineEvent():
return baseline(_that);case AccountUsageChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AccountUsageBaselineEvent value)?  baseline,TResult? Function( AccountUsageChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case AccountUsageBaselineEvent() when baseline != null:
return baseline(_that);case AccountUsageChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AccountUsageBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AccountUsageChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AccountUsageBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case AccountUsageChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AccountUsageBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AccountUsageChange value)  change,}) {final _that = this;
switch (_that) {
case AccountUsageBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case AccountUsageChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AccountUsageBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  AccountUsageChange value)?  change,}) {final _that = this;
switch (_that) {
case AccountUsageBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case AccountUsageChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class AccountUsageBaselineEvent implements AccountUsageEvent {
  const AccountUsageBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  AccountUsageBaseline value;

/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageBaselineEventCopyWith<AccountUsageBaselineEvent> get copyWith => _$AccountUsageBaselineEventCopyWithImpl<AccountUsageBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $AccountUsageBaselineEventCopyWith<$Res> implements $AccountUsageEventCopyWith<$Res> {
  factory $AccountUsageBaselineEventCopyWith(AccountUsageBaselineEvent value, $Res Function(AccountUsageBaselineEvent) _then) = _$AccountUsageBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, AccountUsageBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$AccountUsageBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$AccountUsageBaselineEventCopyWithImpl<$Res>
    implements $AccountUsageBaselineEventCopyWith<$Res> {
  _$AccountUsageBaselineEventCopyWithImpl(this._self, this._then);

  final AccountUsageBaselineEvent _self;
  final $Res Function(AccountUsageBaselineEvent) _then;

/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(AccountUsageBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AccountUsageBaseline,
  ));
}

/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageBaselineCopyWith<$Res> get value {

  return $AccountUsageBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class AccountUsageChangeEvent implements AccountUsageEvent {
  const AccountUsageChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  AccountUsageChange value;

/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageChangeEventCopyWith<AccountUsageChangeEvent> get copyWith => _$AccountUsageChangeEventCopyWithImpl<AccountUsageChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}



}

/// @nodoc
abstract mixin class $AccountUsageChangeEventCopyWith<$Res> implements $AccountUsageEventCopyWith<$Res> {
  factory $AccountUsageChangeEventCopyWith(AccountUsageChangeEvent value, $Res Function(AccountUsageChangeEvent) _then) = _$AccountUsageChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, AccountUsageChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$AccountUsageChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$AccountUsageChangeEventCopyWithImpl<$Res>
    implements $AccountUsageChangeEventCopyWith<$Res> {
  _$AccountUsageChangeEventCopyWithImpl(this._self, this._then);

  final AccountUsageChangeEvent _self;
  final $Res Function(AccountUsageChangeEvent) _then;

/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(AccountUsageChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AccountUsageChange,
  ));
}

/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AccountUsageEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageChangeCopyWith<$Res> get value {

  return $AccountUsageChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$AccountUsageBaseline {

 AccountUsageHeader get header; ProductCollectionRef? get collection;
/// Create a copy of AccountUsageBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageBaselineCopyWith<AccountUsageBaseline> get copyWith => _$AccountUsageBaselineCopyWithImpl<AccountUsageBaseline>(this as AccountUsageBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as AccountUsageBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}



}

/// @nodoc
abstract mixin class $AccountUsageBaselineCopyWith<$Res>  {
  factory $AccountUsageBaselineCopyWith(AccountUsageBaseline value, $Res Function(AccountUsageBaseline) _then) = _$AccountUsageBaselineCopyWithImpl;
@useResult
$Res call({
 AccountUsageHeader header, ProductCollectionRef? collection
});


$AccountUsageHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$AccountUsageBaselineCopyWithImpl<$Res>
    implements $AccountUsageBaselineCopyWith<$Res> {
  _$AccountUsageBaselineCopyWithImpl(this._self, this._then);

  final AccountUsageBaseline _self;
  final $Res Function(AccountUsageBaseline) _then;

/// Create a copy of AccountUsageBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(AccountUsageBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AccountUsageHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of AccountUsageBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageHeaderCopyWith<$Res> get header {

  return $AccountUsageHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AccountUsageBaseline
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


/// Adds pattern-matching-related methods to [AccountUsageBaseline].
extension AccountUsageBaselinePatterns on AccountUsageBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageBaseline value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountUsageHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountUsageHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountUsageHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageBaseline implements AccountUsageBaseline {
  const _AccountUsageBaseline({required this.header, required this.collection});


@override final  AccountUsageHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of AccountUsageBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageBaselineCopyWith<_AccountUsageBaseline> get copyWith => __$AccountUsageBaselineCopyWithImpl<_AccountUsageBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}



}

/// @nodoc
abstract mixin class _$AccountUsageBaselineCopyWith<$Res> implements $AccountUsageBaselineCopyWith<$Res> {
  factory _$AccountUsageBaselineCopyWith(_AccountUsageBaseline value, $Res Function(_AccountUsageBaseline) _then) = __$AccountUsageBaselineCopyWithImpl;
@override @useResult
$Res call({
 AccountUsageHeader header, ProductCollectionRef? collection
});


@override $AccountUsageHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$AccountUsageBaselineCopyWithImpl<$Res>
    implements _$AccountUsageBaselineCopyWith<$Res> {
  __$AccountUsageBaselineCopyWithImpl(this._self, this._then);

  final _AccountUsageBaseline _self;
  final $Res Function(_AccountUsageBaseline) _then;

/// Create a copy of AccountUsageBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_AccountUsageBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AccountUsageHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of AccountUsageBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageHeaderCopyWith<$Res> get header {

  return $AccountUsageHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AccountUsageBaseline
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
mixin _$AccountUsageChange {

 AccountUsageHeader get header; int? get baseCollectionRevision; ProductCollectionRef? get collection; List<ProductEntityRef> get upserted; List<int> get removedEntries;
/// Create a copy of AccountUsageChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageChangeCopyWith<AccountUsageChange> get copyWith => _$AccountUsageChangeCopyWithImpl<AccountUsageChange>(this as AccountUsageChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as AccountUsageChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $AccountUsageChangeCopyWith<$Res>  {
  factory $AccountUsageChangeCopyWith(AccountUsageChange value, $Res Function(AccountUsageChange) _then) = _$AccountUsageChangeCopyWithImpl;
@useResult
$Res call({
 AccountUsageHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$AccountUsageHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$AccountUsageChangeCopyWithImpl<$Res>
    implements $AccountUsageChangeCopyWith<$Res> {
  _$AccountUsageChangeCopyWithImpl(this._self, this._then);

  final AccountUsageChange _self;
  final $Res Function(AccountUsageChange) _then;

/// Create a copy of AccountUsageChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(AccountUsageChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AccountUsageHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of AccountUsageChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageHeaderCopyWith<$Res> get header {

  return $AccountUsageHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AccountUsageChange
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


/// Adds pattern-matching-related methods to [AccountUsageChange].
extension AccountUsageChangePatterns on AccountUsageChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageChange() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageChange value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageChange():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageChange value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageChange() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountUsageHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageChange() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountUsageHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageChange():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountUsageHeader header,  int? baseCollectionRevision,  ProductCollectionRef? collection,  List<ProductEntityRef> upserted,  List<int> removedEntries)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageChange() when $default != null:
return $default(_that.header,_that.baseCollectionRevision,_that.collection,_that.upserted,_that.removedEntries);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageChange implements AccountUsageChange {
  const _AccountUsageChange({required this.header, required this.baseCollectionRevision, required this.collection, required  List<ProductEntityRef> upserted, required  List<int> removedEntries}): _upserted = upserted,_removedEntries = removedEntries;


@override final  AccountUsageHeader header;
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


/// Create a copy of AccountUsageChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageChangeCopyWith<_AccountUsageChange> get copyWith => __$AccountUsageChangeCopyWithImpl<_AccountUsageChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageChange&&(identical(other.header, header) || other.header == header)&&(identical(other.baseCollectionRevision, baseCollectionRevision) || other.baseCollectionRevision == baseCollectionRevision)&&(identical(other.collection, collection) || other.collection == collection)&&const DeepCollectionEquality().equals(other.upserted, _upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _removedEntries));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,baseCollectionRevision,collection,const DeepCollectionEquality().hash(_upserted),const DeepCollectionEquality().hash(_removedEntries));
}



}

/// @nodoc
abstract mixin class _$AccountUsageChangeCopyWith<$Res> implements $AccountUsageChangeCopyWith<$Res> {
  factory _$AccountUsageChangeCopyWith(_AccountUsageChange value, $Res Function(_AccountUsageChange) _then) = __$AccountUsageChangeCopyWithImpl;
@override @useResult
$Res call({
 AccountUsageHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


@override $AccountUsageHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$AccountUsageChangeCopyWithImpl<$Res>
    implements _$AccountUsageChangeCopyWith<$Res> {
  __$AccountUsageChangeCopyWithImpl(this._self, this._then);

  final _AccountUsageChange _self;
  final $Res Function(_AccountUsageChange) _then;

/// Create a copy of AccountUsageChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(_AccountUsageChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AccountUsageHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self._upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self._removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}

/// Create a copy of AccountUsageChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageHeaderCopyWith<$Res> get header {

  return $AccountUsageHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AccountUsageChange
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
