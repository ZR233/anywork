// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeStatisticsFeedEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStatisticsFeedEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeStatisticsFeedEvent()';
}


}

/// @nodoc
class $BridgeStatisticsFeedEventCopyWith<$Res>  {
$BridgeStatisticsFeedEventCopyWith(BridgeStatisticsFeedEvent _, $Res Function(BridgeStatisticsFeedEvent) __);
}


/// Adds pattern-matching-related methods to [BridgeStatisticsFeedEvent].
extension BridgeStatisticsFeedEventPatterns on BridgeStatisticsFeedEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeStatisticsFeedEvent_Baseline value)?  baseline,TResult Function( BridgeStatisticsFeedEvent_Data value)?  data,TResult Function( BridgeStatisticsFeedEvent_Failure value)?  failure,TResult Function( BridgeStatisticsFeedEvent_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeStatisticsFeedEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeStatisticsFeedEvent_Data() when data != null:
return data(_that);case BridgeStatisticsFeedEvent_Failure() when failure != null:
return failure(_that);case BridgeStatisticsFeedEvent_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeStatisticsFeedEvent_Baseline value)  baseline,required TResult Function( BridgeStatisticsFeedEvent_Data value)  data,required TResult Function( BridgeStatisticsFeedEvent_Failure value)  failure,required TResult Function( BridgeStatisticsFeedEvent_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeStatisticsFeedEvent_Baseline():
return baseline(_that);case BridgeStatisticsFeedEvent_Data():
return data(_that);case BridgeStatisticsFeedEvent_Failure():
return failure(_that);case BridgeStatisticsFeedEvent_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeStatisticsFeedEvent_Baseline value)?  baseline,TResult? Function( BridgeStatisticsFeedEvent_Data value)?  data,TResult? Function( BridgeStatisticsFeedEvent_Failure value)?  failure,TResult? Function( BridgeStatisticsFeedEvent_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeStatisticsFeedEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeStatisticsFeedEvent_Data() when data != null:
return data(_that);case BridgeStatisticsFeedEvent_Failure() when failure != null:
return failure(_that);case BridgeStatisticsFeedEvent_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeStatisticsFeedHeader publication)?  baseline,TResult Function( BridgeStatisticsFeedHeader publication)?  data,TResult Function( BridgeError error)?  failure,TResult Function()?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeStatisticsFeedEvent_Baseline() when baseline != null:
return baseline(_that.publication);case BridgeStatisticsFeedEvent_Data() when data != null:
return data(_that.publication);case BridgeStatisticsFeedEvent_Failure() when failure != null:
return failure(_that.error);case BridgeStatisticsFeedEvent_Closed() when closed != null:
return closed();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeStatisticsFeedHeader publication)  baseline,required TResult Function( BridgeStatisticsFeedHeader publication)  data,required TResult Function( BridgeError error)  failure,required TResult Function()  closed,}) {final _that = this;
switch (_that) {
case BridgeStatisticsFeedEvent_Baseline():
return baseline(_that.publication);case BridgeStatisticsFeedEvent_Data():
return data(_that.publication);case BridgeStatisticsFeedEvent_Failure():
return failure(_that.error);case BridgeStatisticsFeedEvent_Closed():
return closed();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeStatisticsFeedHeader publication)?  baseline,TResult? Function( BridgeStatisticsFeedHeader publication)?  data,TResult? Function( BridgeError error)?  failure,TResult? Function()?  closed,}) {final _that = this;
switch (_that) {
case BridgeStatisticsFeedEvent_Baseline() when baseline != null:
return baseline(_that.publication);case BridgeStatisticsFeedEvent_Data() when data != null:
return data(_that.publication);case BridgeStatisticsFeedEvent_Failure() when failure != null:
return failure(_that.error);case BridgeStatisticsFeedEvent_Closed() when closed != null:
return closed();case _:
  return null;

}
}

}

/// @nodoc


class BridgeStatisticsFeedEvent_Baseline extends BridgeStatisticsFeedEvent {
  const BridgeStatisticsFeedEvent_Baseline({required this.publication}): super._();


 final  BridgeStatisticsFeedHeader publication;

/// Create a copy of BridgeStatisticsFeedEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStatisticsFeedEvent_BaselineCopyWith<BridgeStatisticsFeedEvent_Baseline> get copyWith => _$BridgeStatisticsFeedEvent_BaselineCopyWithImpl<BridgeStatisticsFeedEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStatisticsFeedEvent_Baseline&&(identical(other.publication, publication) || other.publication == publication));
}


@override
int get hashCode {
    return Object.hash(runtimeType,publication);
}

@override
String toString() {
    return 'BridgeStatisticsFeedEvent.baseline(publication: $publication)';
}


}

/// @nodoc
abstract mixin class $BridgeStatisticsFeedEvent_BaselineCopyWith<$Res> implements $BridgeStatisticsFeedEventCopyWith<$Res> {
  factory $BridgeStatisticsFeedEvent_BaselineCopyWith(BridgeStatisticsFeedEvent_Baseline value, $Res Function(BridgeStatisticsFeedEvent_Baseline) _then) = _$BridgeStatisticsFeedEvent_BaselineCopyWithImpl;
@useResult
$Res call({
 BridgeStatisticsFeedHeader publication
});




}
/// @nodoc
class _$BridgeStatisticsFeedEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeStatisticsFeedEvent_BaselineCopyWith<$Res> {
  _$BridgeStatisticsFeedEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeStatisticsFeedEvent_Baseline _self;
  final $Res Function(BridgeStatisticsFeedEvent_Baseline) _then;

/// Create a copy of BridgeStatisticsFeedEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? publication = null,}) {
  return _then(BridgeStatisticsFeedEvent_Baseline(
publication: null == publication ? _self.publication : publication // ignore: cast_nullable_to_non_nullable
as BridgeStatisticsFeedHeader,
  ));
}


}

/// @nodoc


class BridgeStatisticsFeedEvent_Data extends BridgeStatisticsFeedEvent {
  const BridgeStatisticsFeedEvent_Data({required this.publication}): super._();


 final  BridgeStatisticsFeedHeader publication;

/// Create a copy of BridgeStatisticsFeedEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStatisticsFeedEvent_DataCopyWith<BridgeStatisticsFeedEvent_Data> get copyWith => _$BridgeStatisticsFeedEvent_DataCopyWithImpl<BridgeStatisticsFeedEvent_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStatisticsFeedEvent_Data&&(identical(other.publication, publication) || other.publication == publication));
}


@override
int get hashCode {
    return Object.hash(runtimeType,publication);
}

@override
String toString() {
    return 'BridgeStatisticsFeedEvent.data(publication: $publication)';
}


}

/// @nodoc
abstract mixin class $BridgeStatisticsFeedEvent_DataCopyWith<$Res> implements $BridgeStatisticsFeedEventCopyWith<$Res> {
  factory $BridgeStatisticsFeedEvent_DataCopyWith(BridgeStatisticsFeedEvent_Data value, $Res Function(BridgeStatisticsFeedEvent_Data) _then) = _$BridgeStatisticsFeedEvent_DataCopyWithImpl;
@useResult
$Res call({
 BridgeStatisticsFeedHeader publication
});




}
/// @nodoc
class _$BridgeStatisticsFeedEvent_DataCopyWithImpl<$Res>
    implements $BridgeStatisticsFeedEvent_DataCopyWith<$Res> {
  _$BridgeStatisticsFeedEvent_DataCopyWithImpl(this._self, this._then);

  final BridgeStatisticsFeedEvent_Data _self;
  final $Res Function(BridgeStatisticsFeedEvent_Data) _then;

/// Create a copy of BridgeStatisticsFeedEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? publication = null,}) {
  return _then(BridgeStatisticsFeedEvent_Data(
publication: null == publication ? _self.publication : publication // ignore: cast_nullable_to_non_nullable
as BridgeStatisticsFeedHeader,
  ));
}


}

/// @nodoc


class BridgeStatisticsFeedEvent_Failure extends BridgeStatisticsFeedEvent {
  const BridgeStatisticsFeedEvent_Failure({required this.error}): super._();


 final  BridgeError error;

/// Create a copy of BridgeStatisticsFeedEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStatisticsFeedEvent_FailureCopyWith<BridgeStatisticsFeedEvent_Failure> get copyWith => _$BridgeStatisticsFeedEvent_FailureCopyWithImpl<BridgeStatisticsFeedEvent_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStatisticsFeedEvent_Failure&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeStatisticsFeedEvent.failure(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeStatisticsFeedEvent_FailureCopyWith<$Res> implements $BridgeStatisticsFeedEventCopyWith<$Res> {
  factory $BridgeStatisticsFeedEvent_FailureCopyWith(BridgeStatisticsFeedEvent_Failure value, $Res Function(BridgeStatisticsFeedEvent_Failure) _then) = _$BridgeStatisticsFeedEvent_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeStatisticsFeedEvent_FailureCopyWithImpl<$Res>
    implements $BridgeStatisticsFeedEvent_FailureCopyWith<$Res> {
  _$BridgeStatisticsFeedEvent_FailureCopyWithImpl(this._self, this._then);

  final BridgeStatisticsFeedEvent_Failure _self;
  final $Res Function(BridgeStatisticsFeedEvent_Failure) _then;

/// Create a copy of BridgeStatisticsFeedEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeStatisticsFeedEvent_Failure(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeStatisticsFeedEvent_Closed extends BridgeStatisticsFeedEvent {
  const BridgeStatisticsFeedEvent_Closed(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStatisticsFeedEvent_Closed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeStatisticsFeedEvent.closed()';
}


}




// dart format on
