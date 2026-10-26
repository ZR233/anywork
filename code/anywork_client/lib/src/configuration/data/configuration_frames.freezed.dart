// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'configuration_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConfigurationFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ConfigurationFrameCopyWith<$Res>  {
$ConfigurationFrameCopyWith(ConfigurationFrame _, $Res Function(ConfigurationFrame) __);
}


/// Adds pattern-matching-related methods to [ConfigurationFrame].
extension ConfigurationFramePatterns on ConfigurationFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ConfigurationData value)?  data,TResult Function( ConfigurationResyncRequired value)?  resyncRequired,TResult Function( ConfigurationFeedFailure value)?  failure,TResult Function( ConfigurationClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ConfigurationData() when data != null:
return data(_that);case ConfigurationResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ConfigurationFeedFailure() when failure != null:
return failure(_that);case ConfigurationClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ConfigurationData value)  data,required TResult Function( ConfigurationResyncRequired value)  resyncRequired,required TResult Function( ConfigurationFeedFailure value)  failure,required TResult Function( ConfigurationClosed value)  closed,}){
final _that = this;
switch (_that) {
case ConfigurationData():
return data(_that);case ConfigurationResyncRequired():
return resyncRequired(_that);case ConfigurationFeedFailure():
return failure(_that);case ConfigurationClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ConfigurationData value)?  data,TResult? Function( ConfigurationResyncRequired value)?  resyncRequired,TResult? Function( ConfigurationFeedFailure value)?  failure,TResult? Function( ConfigurationClosed value)?  closed,}){
final _that = this;
switch (_that) {
case ConfigurationData() when data != null:
return data(_that);case ConfigurationResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ConfigurationFeedFailure() when failure != null:
return failure(_that);case ConfigurationClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  ConfigurationEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ConfigurationData() when data != null:
return data(_that.deliverySequence,_that.event);case ConfigurationResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ConfigurationFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case ConfigurationClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  ConfigurationEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case ConfigurationData():
return data(_that.deliverySequence,_that.event);case ConfigurationResyncRequired():
return resyncRequired(_that.identity,_that.reason);case ConfigurationFeedFailure():
return failure(_that.identity,_that.error);case ConfigurationClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  ConfigurationEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case ConfigurationData() when data != null:
return data(_that.deliverySequence,_that.event);case ConfigurationResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ConfigurationFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case ConfigurationClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ConfigurationData implements ConfigurationFrame {
  const ConfigurationData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  ConfigurationEvent event;

/// Create a copy of ConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationDataCopyWith<ConfigurationData> get copyWith => _$ConfigurationDataCopyWithImpl<ConfigurationData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $ConfigurationDataCopyWith<$Res> implements $ConfigurationFrameCopyWith<$Res> {
  factory $ConfigurationDataCopyWith(ConfigurationData value, $Res Function(ConfigurationData) _then) = _$ConfigurationDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, ConfigurationEvent event
});


$ConfigurationEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ConfigurationDataCopyWithImpl<$Res>
    implements $ConfigurationDataCopyWith<$Res> {
  _$ConfigurationDataCopyWithImpl(this._self, this._then);

  final ConfigurationData _self;
  final $Res Function(ConfigurationData) _then;

/// Create a copy of ConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(ConfigurationData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ConfigurationEvent,
  ));
}

/// Create a copy of ConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationEventCopyWith<$Res> get event {

  return $ConfigurationEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ConfigurationResyncRequired implements ConfigurationFrame {
  const ConfigurationResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of ConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationResyncRequiredCopyWith<ConfigurationResyncRequired> get copyWith => _$ConfigurationResyncRequiredCopyWithImpl<ConfigurationResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ConfigurationResyncRequiredCopyWith<$Res> implements $ConfigurationFrameCopyWith<$Res> {
  factory $ConfigurationResyncRequiredCopyWith(ConfigurationResyncRequired value, $Res Function(ConfigurationResyncRequired) _then) = _$ConfigurationResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ConfigurationResyncRequiredCopyWithImpl<$Res>
    implements $ConfigurationResyncRequiredCopyWith<$Res> {
  _$ConfigurationResyncRequiredCopyWithImpl(this._self, this._then);

  final ConfigurationResyncRequired _self;
  final $Res Function(ConfigurationResyncRequired) _then;

/// Create a copy of ConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ConfigurationResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of ConfigurationFrame
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


class ConfigurationFeedFailure implements ConfigurationFrame {
  const ConfigurationFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of ConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationFeedFailureCopyWith<ConfigurationFeedFailure> get copyWith => _$ConfigurationFeedFailureCopyWithImpl<ConfigurationFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $ConfigurationFeedFailureCopyWith<$Res> implements $ConfigurationFrameCopyWith<$Res> {
  factory $ConfigurationFeedFailureCopyWith(ConfigurationFeedFailure value, $Res Function(ConfigurationFeedFailure) _then) = _$ConfigurationFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$ConfigurationFeedFailureCopyWithImpl<$Res>
    implements $ConfigurationFeedFailureCopyWith<$Res> {
  _$ConfigurationFeedFailureCopyWithImpl(this._self, this._then);

  final ConfigurationFeedFailure _self;
  final $Res Function(ConfigurationFeedFailure) _then;

/// Create a copy of ConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(ConfigurationFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ConfigurationFrame
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


class ConfigurationClosed implements ConfigurationFrame {
  const ConfigurationClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of ConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationClosedCopyWith<ConfigurationClosed> get copyWith => _$ConfigurationClosedCopyWithImpl<ConfigurationClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ConfigurationClosedCopyWith<$Res> implements $ConfigurationFrameCopyWith<$Res> {
  factory $ConfigurationClosedCopyWith(ConfigurationClosed value, $Res Function(ConfigurationClosed) _then) = _$ConfigurationClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ConfigurationClosedCopyWithImpl<$Res>
    implements $ConfigurationClosedCopyWith<$Res> {
  _$ConfigurationClosedCopyWithImpl(this._self, this._then);

  final ConfigurationClosed _self;
  final $Res Function(ConfigurationClosed) _then;

/// Create a copy of ConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ConfigurationClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of ConfigurationFrame
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
mixin _$ConfigurationEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationEventCopyWith<ConfigurationEvent> get copyWith => _$ConfigurationEventCopyWithImpl<ConfigurationEvent>(this as ConfigurationEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as ConfigurationEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}



}

/// @nodoc
abstract mixin class $ConfigurationEventCopyWith<$Res>  {
  factory $ConfigurationEventCopyWith(ConfigurationEvent value, $Res Function(ConfigurationEvent) _then) = _$ConfigurationEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$ConfigurationEventCopyWithImpl<$Res>
    implements $ConfigurationEventCopyWith<$Res> {
  _$ConfigurationEventCopyWithImpl(this._self, this._then);

  final ConfigurationEvent _self;
  final $Res Function(ConfigurationEvent) _then;

/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConfigurationEvent].
extension ConfigurationEventPatterns on ConfigurationEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ConfigurationBaselineEvent value)?  baseline,TResult Function( ConfigurationChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ConfigurationBaselineEvent() when baseline != null:
return baseline(_that);case ConfigurationChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ConfigurationBaselineEvent value)  baseline,required TResult Function( ConfigurationChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case ConfigurationBaselineEvent():
return baseline(_that);case ConfigurationChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ConfigurationBaselineEvent value)?  baseline,TResult? Function( ConfigurationChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case ConfigurationBaselineEvent() when baseline != null:
return baseline(_that);case ConfigurationChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ConfigurationBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  ConfigurationChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ConfigurationBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ConfigurationChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ConfigurationBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  ConfigurationChange value)  change,}) {final _that = this;
switch (_that) {
case ConfigurationBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case ConfigurationChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ConfigurationBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  ConfigurationChange value)?  change,}) {final _that = this;
switch (_that) {
case ConfigurationBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ConfigurationChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ConfigurationBaselineEvent implements ConfigurationEvent {
  const ConfigurationBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  ConfigurationBaseline value;

/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationBaselineEventCopyWith<ConfigurationBaselineEvent> get copyWith => _$ConfigurationBaselineEventCopyWithImpl<ConfigurationBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $ConfigurationBaselineEventCopyWith<$Res> implements $ConfigurationEventCopyWith<$Res> {
  factory $ConfigurationBaselineEventCopyWith(ConfigurationBaselineEvent value, $Res Function(ConfigurationBaselineEvent) _then) = _$ConfigurationBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, ConfigurationBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$ConfigurationBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$ConfigurationBaselineEventCopyWithImpl<$Res>
    implements $ConfigurationBaselineEventCopyWith<$Res> {
  _$ConfigurationBaselineEventCopyWithImpl(this._self, this._then);

  final ConfigurationBaselineEvent _self;
  final $Res Function(ConfigurationBaselineEvent) _then;

/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(ConfigurationBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ConfigurationBaseline,
  ));
}

/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationBaselineCopyWith<$Res> get value {

  return $ConfigurationBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class ConfigurationChangeEvent implements ConfigurationEvent {
  const ConfigurationChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  ConfigurationChange value;

/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationChangeEventCopyWith<ConfigurationChangeEvent> get copyWith => _$ConfigurationChangeEventCopyWithImpl<ConfigurationChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}



}

/// @nodoc
abstract mixin class $ConfigurationChangeEventCopyWith<$Res> implements $ConfigurationEventCopyWith<$Res> {
  factory $ConfigurationChangeEventCopyWith(ConfigurationChangeEvent value, $Res Function(ConfigurationChangeEvent) _then) = _$ConfigurationChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, ConfigurationChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$ConfigurationChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$ConfigurationChangeEventCopyWithImpl<$Res>
    implements $ConfigurationChangeEventCopyWith<$Res> {
  _$ConfigurationChangeEventCopyWithImpl(this._self, this._then);

  final ConfigurationChangeEvent _self;
  final $Res Function(ConfigurationChangeEvent) _then;

/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(ConfigurationChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ConfigurationChange,
  ));
}

/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationChangeCopyWith<$Res> get value {

  return $ConfigurationChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ConfigurationBaseline {

 ConfigurationHeader get header; ProductCollectionRef? get collection;
/// Create a copy of ConfigurationBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationBaselineCopyWith<ConfigurationBaseline> get copyWith => _$ConfigurationBaselineCopyWithImpl<ConfigurationBaseline>(this as ConfigurationBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as ConfigurationBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}



}

/// @nodoc
abstract mixin class $ConfigurationBaselineCopyWith<$Res>  {
  factory $ConfigurationBaselineCopyWith(ConfigurationBaseline value, $Res Function(ConfigurationBaseline) _then) = _$ConfigurationBaselineCopyWithImpl;
@useResult
$Res call({
 ConfigurationHeader header, ProductCollectionRef? collection
});


$ConfigurationHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$ConfigurationBaselineCopyWithImpl<$Res>
    implements $ConfigurationBaselineCopyWith<$Res> {
  _$ConfigurationBaselineCopyWithImpl(this._self, this._then);

  final ConfigurationBaseline _self;
  final $Res Function(ConfigurationBaseline) _then;

/// Create a copy of ConfigurationBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(ConfigurationBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ConfigurationHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of ConfigurationBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationHeaderCopyWith<$Res> get header {

  return $ConfigurationHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ConfigurationBaseline
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


/// Adds pattern-matching-related methods to [ConfigurationBaseline].
extension ConfigurationBaselinePatterns on ConfigurationBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConfigurationBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConfigurationBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConfigurationBaseline value)  $default,){
final _that = this;
switch (_that) {
case _ConfigurationBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConfigurationBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _ConfigurationBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigurationHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConfigurationBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigurationHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _ConfigurationBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigurationHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _ConfigurationBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _ConfigurationBaseline implements ConfigurationBaseline {
  const _ConfigurationBaseline({required this.header, required this.collection});


@override final  ConfigurationHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of ConfigurationBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConfigurationBaselineCopyWith<_ConfigurationBaseline> get copyWith => __$ConfigurationBaselineCopyWithImpl<_ConfigurationBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConfigurationBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}



}

/// @nodoc
abstract mixin class _$ConfigurationBaselineCopyWith<$Res> implements $ConfigurationBaselineCopyWith<$Res> {
  factory _$ConfigurationBaselineCopyWith(_ConfigurationBaseline value, $Res Function(_ConfigurationBaseline) _then) = __$ConfigurationBaselineCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationHeader header, ProductCollectionRef? collection
});


@override $ConfigurationHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$ConfigurationBaselineCopyWithImpl<$Res>
    implements _$ConfigurationBaselineCopyWith<$Res> {
  __$ConfigurationBaselineCopyWithImpl(this._self, this._then);

  final _ConfigurationBaseline _self;
  final $Res Function(_ConfigurationBaseline) _then;

/// Create a copy of ConfigurationBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_ConfigurationBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ConfigurationHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of ConfigurationBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationHeaderCopyWith<$Res> get header {

  return $ConfigurationHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ConfigurationBaseline
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
mixin _$ConfigurationChange {


/// Create a copy of ConfigurationChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationChangeCopyWith<ConfigurationChange> get copyWith => _$ConfigurationChangeCopyWithImpl<ConfigurationChange>(this as ConfigurationChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as ConfigurationChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $ConfigurationChangeCopyWith<$Res>  {
  factory $ConfigurationChangeCopyWith(ConfigurationChange value, $Res Function(ConfigurationChange) _then) = _$ConfigurationChangeCopyWithImpl;
@useResult
$Res call({
 ConfigurationHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$ConfigurationHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$ConfigurationChangeCopyWithImpl<$Res>
    implements $ConfigurationChangeCopyWith<$Res> {
  _$ConfigurationChangeCopyWithImpl(this._self, this._then);

  final ConfigurationChange _self;
  final $Res Function(ConfigurationChange) _then;

/// Create a copy of ConfigurationChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(ConfigurationChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ConfigurationHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of ConfigurationChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationHeaderCopyWith<$Res> get header {

  return $ConfigurationHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ConfigurationChange
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


/// Adds pattern-matching-related methods to [ConfigurationChange].
extension ConfigurationChangePatterns on ConfigurationChange {
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
mixin _$AgentProfilesFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AgentProfilesFrameCopyWith<$Res>  {
$AgentProfilesFrameCopyWith(AgentProfilesFrame _, $Res Function(AgentProfilesFrame) __);
}


/// Adds pattern-matching-related methods to [AgentProfilesFrame].
extension AgentProfilesFramePatterns on AgentProfilesFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AgentProfilesData value)?  data,TResult Function( AgentProfilesResyncRequired value)?  resyncRequired,TResult Function( AgentProfilesFeedFailure value)?  failure,TResult Function( AgentProfilesClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AgentProfilesData() when data != null:
return data(_that);case AgentProfilesResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AgentProfilesFeedFailure() when failure != null:
return failure(_that);case AgentProfilesClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AgentProfilesData value)  data,required TResult Function( AgentProfilesResyncRequired value)  resyncRequired,required TResult Function( AgentProfilesFeedFailure value)  failure,required TResult Function( AgentProfilesClosed value)  closed,}){
final _that = this;
switch (_that) {
case AgentProfilesData():
return data(_that);case AgentProfilesResyncRequired():
return resyncRequired(_that);case AgentProfilesFeedFailure():
return failure(_that);case AgentProfilesClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AgentProfilesData value)?  data,TResult? Function( AgentProfilesResyncRequired value)?  resyncRequired,TResult? Function( AgentProfilesFeedFailure value)?  failure,TResult? Function( AgentProfilesClosed value)?  closed,}){
final _that = this;
switch (_that) {
case AgentProfilesData() when data != null:
return data(_that);case AgentProfilesResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AgentProfilesFeedFailure() when failure != null:
return failure(_that);case AgentProfilesClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  AgentProfilesEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AgentProfilesData() when data != null:
return data(_that.deliverySequence,_that.event);case AgentProfilesResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AgentProfilesFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AgentProfilesClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  AgentProfilesEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case AgentProfilesData():
return data(_that.deliverySequence,_that.event);case AgentProfilesResyncRequired():
return resyncRequired(_that.identity,_that.reason);case AgentProfilesFeedFailure():
return failure(_that.identity,_that.error);case AgentProfilesClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  AgentProfilesEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case AgentProfilesData() when data != null:
return data(_that.deliverySequence,_that.event);case AgentProfilesResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AgentProfilesFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AgentProfilesClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class AgentProfilesData implements AgentProfilesFrame {
  const AgentProfilesData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  AgentProfilesEvent event;

/// Create a copy of AgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesDataCopyWith<AgentProfilesData> get copyWith => _$AgentProfilesDataCopyWithImpl<AgentProfilesData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $AgentProfilesDataCopyWith<$Res> implements $AgentProfilesFrameCopyWith<$Res> {
  factory $AgentProfilesDataCopyWith(AgentProfilesData value, $Res Function(AgentProfilesData) _then) = _$AgentProfilesDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, AgentProfilesEvent event
});


$AgentProfilesEventCopyWith<$Res> get event;

}
/// @nodoc
class _$AgentProfilesDataCopyWithImpl<$Res>
    implements $AgentProfilesDataCopyWith<$Res> {
  _$AgentProfilesDataCopyWithImpl(this._self, this._then);

  final AgentProfilesData _self;
  final $Res Function(AgentProfilesData) _then;

/// Create a copy of AgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(AgentProfilesData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as AgentProfilesEvent,
  ));
}

/// Create a copy of AgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesEventCopyWith<$Res> get event {

  return $AgentProfilesEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class AgentProfilesResyncRequired implements AgentProfilesFrame {
  const AgentProfilesResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of AgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesResyncRequiredCopyWith<AgentProfilesResyncRequired> get copyWith => _$AgentProfilesResyncRequiredCopyWithImpl<AgentProfilesResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AgentProfilesResyncRequiredCopyWith<$Res> implements $AgentProfilesFrameCopyWith<$Res> {
  factory $AgentProfilesResyncRequiredCopyWith(AgentProfilesResyncRequired value, $Res Function(AgentProfilesResyncRequired) _then) = _$AgentProfilesResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AgentProfilesResyncRequiredCopyWithImpl<$Res>
    implements $AgentProfilesResyncRequiredCopyWith<$Res> {
  _$AgentProfilesResyncRequiredCopyWithImpl(this._self, this._then);

  final AgentProfilesResyncRequired _self;
  final $Res Function(AgentProfilesResyncRequired) _then;

/// Create a copy of AgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AgentProfilesResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of AgentProfilesFrame
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


class AgentProfilesFeedFailure implements AgentProfilesFrame {
  const AgentProfilesFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of AgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesFeedFailureCopyWith<AgentProfilesFeedFailure> get copyWith => _$AgentProfilesFeedFailureCopyWithImpl<AgentProfilesFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $AgentProfilesFeedFailureCopyWith<$Res> implements $AgentProfilesFrameCopyWith<$Res> {
  factory $AgentProfilesFeedFailureCopyWith(AgentProfilesFeedFailure value, $Res Function(AgentProfilesFeedFailure) _then) = _$AgentProfilesFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$AgentProfilesFeedFailureCopyWithImpl<$Res>
    implements $AgentProfilesFeedFailureCopyWith<$Res> {
  _$AgentProfilesFeedFailureCopyWithImpl(this._self, this._then);

  final AgentProfilesFeedFailure _self;
  final $Res Function(AgentProfilesFeedFailure) _then;

/// Create a copy of AgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(AgentProfilesFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of AgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AgentProfilesFrame
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


class AgentProfilesClosed implements AgentProfilesFrame {
  const AgentProfilesClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of AgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesClosedCopyWith<AgentProfilesClosed> get copyWith => _$AgentProfilesClosedCopyWithImpl<AgentProfilesClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AgentProfilesClosedCopyWith<$Res> implements $AgentProfilesFrameCopyWith<$Res> {
  factory $AgentProfilesClosedCopyWith(AgentProfilesClosed value, $Res Function(AgentProfilesClosed) _then) = _$AgentProfilesClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AgentProfilesClosedCopyWithImpl<$Res>
    implements $AgentProfilesClosedCopyWith<$Res> {
  _$AgentProfilesClosedCopyWithImpl(this._self, this._then);

  final AgentProfilesClosed _self;
  final $Res Function(AgentProfilesClosed) _then;

/// Create a copy of AgentProfilesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AgentProfilesClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of AgentProfilesFrame
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
mixin _$AgentProfilesEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesEventCopyWith<AgentProfilesEvent> get copyWith => _$AgentProfilesEventCopyWithImpl<AgentProfilesEvent>(this as AgentProfilesEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfilesEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as AgentProfilesEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}



}

/// @nodoc
abstract mixin class $AgentProfilesEventCopyWith<$Res>  {
  factory $AgentProfilesEventCopyWith(AgentProfilesEvent value, $Res Function(AgentProfilesEvent) _then) = _$AgentProfilesEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$AgentProfilesEventCopyWithImpl<$Res>
    implements $AgentProfilesEventCopyWith<$Res> {
  _$AgentProfilesEventCopyWithImpl(this._self, this._then);

  final AgentProfilesEvent _self;
  final $Res Function(AgentProfilesEvent) _then;

/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentProfilesEvent].
extension AgentProfilesEventPatterns on AgentProfilesEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AgentProfilesBaselineEvent value)?  baseline,TResult Function( AgentProfilesChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AgentProfilesBaselineEvent() when baseline != null:
return baseline(_that);case AgentProfilesChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AgentProfilesBaselineEvent value)  baseline,required TResult Function( AgentProfilesChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case AgentProfilesBaselineEvent():
return baseline(_that);case AgentProfilesChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AgentProfilesBaselineEvent value)?  baseline,TResult? Function( AgentProfilesChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case AgentProfilesBaselineEvent() when baseline != null:
return baseline(_that);case AgentProfilesChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AgentProfilesBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AgentProfilesChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AgentProfilesBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case AgentProfilesChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AgentProfilesBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AgentProfilesChange value)  change,}) {final _that = this;
switch (_that) {
case AgentProfilesBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case AgentProfilesChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AgentProfilesBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  AgentProfilesChange value)?  change,}) {final _that = this;
switch (_that) {
case AgentProfilesBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case AgentProfilesChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class AgentProfilesBaselineEvent implements AgentProfilesEvent {
  const AgentProfilesBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  AgentProfilesBaseline value;

/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesBaselineEventCopyWith<AgentProfilesBaselineEvent> get copyWith => _$AgentProfilesBaselineEventCopyWithImpl<AgentProfilesBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $AgentProfilesBaselineEventCopyWith<$Res> implements $AgentProfilesEventCopyWith<$Res> {
  factory $AgentProfilesBaselineEventCopyWith(AgentProfilesBaselineEvent value, $Res Function(AgentProfilesBaselineEvent) _then) = _$AgentProfilesBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, AgentProfilesBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$AgentProfilesBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$AgentProfilesBaselineEventCopyWithImpl<$Res>
    implements $AgentProfilesBaselineEventCopyWith<$Res> {
  _$AgentProfilesBaselineEventCopyWithImpl(this._self, this._then);

  final AgentProfilesBaselineEvent _self;
  final $Res Function(AgentProfilesBaselineEvent) _then;

/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(AgentProfilesBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AgentProfilesBaseline,
  ));
}

/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesBaselineCopyWith<$Res> get value {

  return $AgentProfilesBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class AgentProfilesChangeEvent implements AgentProfilesEvent {
  const AgentProfilesChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  AgentProfilesChange value;

/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesChangeEventCopyWith<AgentProfilesChangeEvent> get copyWith => _$AgentProfilesChangeEventCopyWithImpl<AgentProfilesChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}



}

/// @nodoc
abstract mixin class $AgentProfilesChangeEventCopyWith<$Res> implements $AgentProfilesEventCopyWith<$Res> {
  factory $AgentProfilesChangeEventCopyWith(AgentProfilesChangeEvent value, $Res Function(AgentProfilesChangeEvent) _then) = _$AgentProfilesChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, AgentProfilesChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$AgentProfilesChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$AgentProfilesChangeEventCopyWithImpl<$Res>
    implements $AgentProfilesChangeEventCopyWith<$Res> {
  _$AgentProfilesChangeEventCopyWithImpl(this._self, this._then);

  final AgentProfilesChangeEvent _self;
  final $Res Function(AgentProfilesChangeEvent) _then;

/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(AgentProfilesChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AgentProfilesChange,
  ));
}

/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AgentProfilesEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesChangeCopyWith<$Res> get value {

  return $AgentProfilesChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$AgentProfilesBaseline {

 AgentProfilesHeader get header; ProductCollectionRef? get collection;
/// Create a copy of AgentProfilesBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesBaselineCopyWith<AgentProfilesBaseline> get copyWith => _$AgentProfilesBaselineCopyWithImpl<AgentProfilesBaseline>(this as AgentProfilesBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfilesBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as AgentProfilesBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}



}

/// @nodoc
abstract mixin class $AgentProfilesBaselineCopyWith<$Res>  {
  factory $AgentProfilesBaselineCopyWith(AgentProfilesBaseline value, $Res Function(AgentProfilesBaseline) _then) = _$AgentProfilesBaselineCopyWithImpl;
@useResult
$Res call({
 AgentProfilesHeader header, ProductCollectionRef? collection
});


$AgentProfilesHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$AgentProfilesBaselineCopyWithImpl<$Res>
    implements $AgentProfilesBaselineCopyWith<$Res> {
  _$AgentProfilesBaselineCopyWithImpl(this._self, this._then);

  final AgentProfilesBaseline _self;
  final $Res Function(AgentProfilesBaseline) _then;

/// Create a copy of AgentProfilesBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(AgentProfilesBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AgentProfilesHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of AgentProfilesBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesHeaderCopyWith<$Res> get header {

  return $AgentProfilesHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AgentProfilesBaseline
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


/// Adds pattern-matching-related methods to [AgentProfilesBaseline].
extension AgentProfilesBaselinePatterns on AgentProfilesBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentProfilesBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentProfilesBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentProfilesBaseline value)  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentProfilesBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AgentProfilesHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentProfilesBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AgentProfilesHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _AgentProfilesBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AgentProfilesHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _AgentProfilesBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _AgentProfilesBaseline implements AgentProfilesBaseline {
  const _AgentProfilesBaseline({required this.header, required this.collection});


@override final  AgentProfilesHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of AgentProfilesBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentProfilesBaselineCopyWith<_AgentProfilesBaseline> get copyWith => __$AgentProfilesBaselineCopyWithImpl<_AgentProfilesBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentProfilesBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}



}

/// @nodoc
abstract mixin class _$AgentProfilesBaselineCopyWith<$Res> implements $AgentProfilesBaselineCopyWith<$Res> {
  factory _$AgentProfilesBaselineCopyWith(_AgentProfilesBaseline value, $Res Function(_AgentProfilesBaseline) _then) = __$AgentProfilesBaselineCopyWithImpl;
@override @useResult
$Res call({
 AgentProfilesHeader header, ProductCollectionRef? collection
});


@override $AgentProfilesHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$AgentProfilesBaselineCopyWithImpl<$Res>
    implements _$AgentProfilesBaselineCopyWith<$Res> {
  __$AgentProfilesBaselineCopyWithImpl(this._self, this._then);

  final _AgentProfilesBaseline _self;
  final $Res Function(_AgentProfilesBaseline) _then;

/// Create a copy of AgentProfilesBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_AgentProfilesBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AgentProfilesHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of AgentProfilesBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesHeaderCopyWith<$Res> get header {

  return $AgentProfilesHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AgentProfilesBaseline
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
mixin _$AgentProfilesChange {


/// Create a copy of AgentProfilesChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesChangeCopyWith<AgentProfilesChange> get copyWith => _$AgentProfilesChangeCopyWithImpl<AgentProfilesChange>(this as AgentProfilesChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfilesChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as AgentProfilesChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $AgentProfilesChangeCopyWith<$Res>  {
  factory $AgentProfilesChangeCopyWith(AgentProfilesChange value, $Res Function(AgentProfilesChange) _then) = _$AgentProfilesChangeCopyWithImpl;
@useResult
$Res call({
 AgentProfilesHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$AgentProfilesHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$AgentProfilesChangeCopyWithImpl<$Res>
    implements $AgentProfilesChangeCopyWith<$Res> {
  _$AgentProfilesChangeCopyWithImpl(this._self, this._then);

  final AgentProfilesChange _self;
  final $Res Function(AgentProfilesChange) _then;

/// Create a copy of AgentProfilesChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(AgentProfilesChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AgentProfilesHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of AgentProfilesChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesHeaderCopyWith<$Res> get header {

  return $AgentProfilesHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AgentProfilesChange
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


/// Adds pattern-matching-related methods to [AgentProfilesChange].
extension AgentProfilesChangePatterns on AgentProfilesChange {
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

// dart format on
