// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'descriptor.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeTimelineAgentOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineAgentOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineAgentOutcome()';
}


}

/// @nodoc
class $BridgeTimelineAgentOutcomeCopyWith<$Res>  {
$BridgeTimelineAgentOutcomeCopyWith(BridgeTimelineAgentOutcome _, $Res Function(BridgeTimelineAgentOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelineAgentOutcome].
extension BridgeTimelineAgentOutcomePatterns on BridgeTimelineAgentOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineAgentOutcome_Succeeded value)?  succeeded,TResult Function( BridgeTimelineAgentOutcome_Denied value)?  denied,TResult Function( BridgeTimelineAgentOutcome_Failed value)?  failed,TResult Function( BridgeTimelineAgentOutcome_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineAgentOutcome_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeTimelineAgentOutcome_Denied() when denied != null:
return denied(_that);case BridgeTimelineAgentOutcome_Failed() when failed != null:
return failed(_that);case BridgeTimelineAgentOutcome_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineAgentOutcome_Succeeded value)  succeeded,required TResult Function( BridgeTimelineAgentOutcome_Denied value)  denied,required TResult Function( BridgeTimelineAgentOutcome_Failed value)  failed,required TResult Function( BridgeTimelineAgentOutcome_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case BridgeTimelineAgentOutcome_Succeeded():
return succeeded(_that);case BridgeTimelineAgentOutcome_Denied():
return denied(_that);case BridgeTimelineAgentOutcome_Failed():
return failed(_that);case BridgeTimelineAgentOutcome_Cancelled():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineAgentOutcome_Succeeded value)?  succeeded,TResult? Function( BridgeTimelineAgentOutcome_Denied value)?  denied,TResult? Function( BridgeTimelineAgentOutcome_Failed value)?  failed,TResult? Function( BridgeTimelineAgentOutcome_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case BridgeTimelineAgentOutcome_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeTimelineAgentOutcome_Denied() when denied != null:
return denied(_that);case BridgeTimelineAgentOutcome_Failed() when failed != null:
return failed(_that);case BridgeTimelineAgentOutcome_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PlatformInt64 completedAt,  String summary)?  succeeded,TResult Function( PlatformInt64 deniedAt,  String reason)?  denied,TResult Function( PlatformInt64 failedAt,  String error)?  failed,TResult Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineAgentOutcome_Succeeded() when succeeded != null:
return succeeded(_that.completedAt,_that.summary);case BridgeTimelineAgentOutcome_Denied() when denied != null:
return denied(_that.deniedAt,_that.reason);case BridgeTimelineAgentOutcome_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case BridgeTimelineAgentOutcome_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PlatformInt64 completedAt,  String summary)  succeeded,required TResult Function( PlatformInt64 deniedAt,  String reason)  denied,required TResult Function( PlatformInt64 failedAt,  String error)  failed,required TResult Function( PlatformInt64 cancelledAt,  String reason)  cancelled,}) {final _that = this;
switch (_that) {
case BridgeTimelineAgentOutcome_Succeeded():
return succeeded(_that.completedAt,_that.summary);case BridgeTimelineAgentOutcome_Denied():
return denied(_that.deniedAt,_that.reason);case BridgeTimelineAgentOutcome_Failed():
return failed(_that.failedAt,_that.error);case BridgeTimelineAgentOutcome_Cancelled():
return cancelled(_that.cancelledAt,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PlatformInt64 completedAt,  String summary)?  succeeded,TResult? Function( PlatformInt64 deniedAt,  String reason)?  denied,TResult? Function( PlatformInt64 failedAt,  String error)?  failed,TResult? Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,}) {final _that = this;
switch (_that) {
case BridgeTimelineAgentOutcome_Succeeded() when succeeded != null:
return succeeded(_that.completedAt,_that.summary);case BridgeTimelineAgentOutcome_Denied() when denied != null:
return denied(_that.deniedAt,_that.reason);case BridgeTimelineAgentOutcome_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case BridgeTimelineAgentOutcome_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineAgentOutcome_Succeeded extends BridgeTimelineAgentOutcome {
  const BridgeTimelineAgentOutcome_Succeeded({required this.completedAt, required this.summary}): super._();


 final  PlatformInt64 completedAt;
 final  String summary;

/// Create a copy of BridgeTimelineAgentOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineAgentOutcome_SucceededCopyWith<BridgeTimelineAgentOutcome_Succeeded> get copyWith => _$BridgeTimelineAgentOutcome_SucceededCopyWithImpl<BridgeTimelineAgentOutcome_Succeeded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineAgentOutcome_Succeeded&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.summary, summary) || other.summary == summary));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt,summary);
}

@override
String toString() {
    return 'BridgeTimelineAgentOutcome.succeeded(completedAt: $completedAt, summary: $summary)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineAgentOutcome_SucceededCopyWith<$Res> implements $BridgeTimelineAgentOutcomeCopyWith<$Res> {
  factory $BridgeTimelineAgentOutcome_SucceededCopyWith(BridgeTimelineAgentOutcome_Succeeded value, $Res Function(BridgeTimelineAgentOutcome_Succeeded) _then) = _$BridgeTimelineAgentOutcome_SucceededCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 completedAt, String summary
});




}
/// @nodoc
class _$BridgeTimelineAgentOutcome_SucceededCopyWithImpl<$Res>
    implements $BridgeTimelineAgentOutcome_SucceededCopyWith<$Res> {
  _$BridgeTimelineAgentOutcome_SucceededCopyWithImpl(this._self, this._then);

  final BridgeTimelineAgentOutcome_Succeeded _self;
  final $Res Function(BridgeTimelineAgentOutcome_Succeeded) _then;

/// Create a copy of BridgeTimelineAgentOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,Object? summary = null,}) {
  return _then(BridgeTimelineAgentOutcome_Succeeded(
completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeTimelineAgentOutcome_Denied extends BridgeTimelineAgentOutcome {
  const BridgeTimelineAgentOutcome_Denied({required this.deniedAt, required this.reason}): super._();


 final  PlatformInt64 deniedAt;
 final  String reason;

/// Create a copy of BridgeTimelineAgentOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineAgentOutcome_DeniedCopyWith<BridgeTimelineAgentOutcome_Denied> get copyWith => _$BridgeTimelineAgentOutcome_DeniedCopyWithImpl<BridgeTimelineAgentOutcome_Denied>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineAgentOutcome_Denied&&(identical(other.deniedAt, deniedAt) || other.deniedAt == deniedAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deniedAt,reason);
}

@override
String toString() {
    return 'BridgeTimelineAgentOutcome.denied(deniedAt: $deniedAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineAgentOutcome_DeniedCopyWith<$Res> implements $BridgeTimelineAgentOutcomeCopyWith<$Res> {
  factory $BridgeTimelineAgentOutcome_DeniedCopyWith(BridgeTimelineAgentOutcome_Denied value, $Res Function(BridgeTimelineAgentOutcome_Denied) _then) = _$BridgeTimelineAgentOutcome_DeniedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 deniedAt, String reason
});




}
/// @nodoc
class _$BridgeTimelineAgentOutcome_DeniedCopyWithImpl<$Res>
    implements $BridgeTimelineAgentOutcome_DeniedCopyWith<$Res> {
  _$BridgeTimelineAgentOutcome_DeniedCopyWithImpl(this._self, this._then);

  final BridgeTimelineAgentOutcome_Denied _self;
  final $Res Function(BridgeTimelineAgentOutcome_Denied) _then;

/// Create a copy of BridgeTimelineAgentOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deniedAt = null,Object? reason = null,}) {
  return _then(BridgeTimelineAgentOutcome_Denied(
deniedAt: null == deniedAt ? _self.deniedAt : deniedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeTimelineAgentOutcome_Failed extends BridgeTimelineAgentOutcome {
  const BridgeTimelineAgentOutcome_Failed({required this.failedAt, required this.error}): super._();


 final  PlatformInt64 failedAt;
 final  String error;

/// Create a copy of BridgeTimelineAgentOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineAgentOutcome_FailedCopyWith<BridgeTimelineAgentOutcome_Failed> get copyWith => _$BridgeTimelineAgentOutcome_FailedCopyWithImpl<BridgeTimelineAgentOutcome_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineAgentOutcome_Failed&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,error);
}

@override
String toString() {
    return 'BridgeTimelineAgentOutcome.failed(failedAt: $failedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineAgentOutcome_FailedCopyWith<$Res> implements $BridgeTimelineAgentOutcomeCopyWith<$Res> {
  factory $BridgeTimelineAgentOutcome_FailedCopyWith(BridgeTimelineAgentOutcome_Failed value, $Res Function(BridgeTimelineAgentOutcome_Failed) _then) = _$BridgeTimelineAgentOutcome_FailedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 failedAt, String error
});




}
/// @nodoc
class _$BridgeTimelineAgentOutcome_FailedCopyWithImpl<$Res>
    implements $BridgeTimelineAgentOutcome_FailedCopyWith<$Res> {
  _$BridgeTimelineAgentOutcome_FailedCopyWithImpl(this._self, this._then);

  final BridgeTimelineAgentOutcome_Failed _self;
  final $Res Function(BridgeTimelineAgentOutcome_Failed) _then;

/// Create a copy of BridgeTimelineAgentOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? error = null,}) {
  return _then(BridgeTimelineAgentOutcome_Failed(
failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeTimelineAgentOutcome_Cancelled extends BridgeTimelineAgentOutcome {
  const BridgeTimelineAgentOutcome_Cancelled({required this.cancelledAt, required this.reason}): super._();


 final  PlatformInt64 cancelledAt;
 final  String reason;

/// Create a copy of BridgeTimelineAgentOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineAgentOutcome_CancelledCopyWith<BridgeTimelineAgentOutcome_Cancelled> get copyWith => _$BridgeTimelineAgentOutcome_CancelledCopyWithImpl<BridgeTimelineAgentOutcome_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineAgentOutcome_Cancelled&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}

@override
String toString() {
    return 'BridgeTimelineAgentOutcome.cancelled(cancelledAt: $cancelledAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineAgentOutcome_CancelledCopyWith<$Res> implements $BridgeTimelineAgentOutcomeCopyWith<$Res> {
  factory $BridgeTimelineAgentOutcome_CancelledCopyWith(BridgeTimelineAgentOutcome_Cancelled value, $Res Function(BridgeTimelineAgentOutcome_Cancelled) _then) = _$BridgeTimelineAgentOutcome_CancelledCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 cancelledAt, String reason
});




}
/// @nodoc
class _$BridgeTimelineAgentOutcome_CancelledCopyWithImpl<$Res>
    implements $BridgeTimelineAgentOutcome_CancelledCopyWith<$Res> {
  _$BridgeTimelineAgentOutcome_CancelledCopyWithImpl(this._self, this._then);

  final BridgeTimelineAgentOutcome_Cancelled _self;
  final $Res Function(BridgeTimelineAgentOutcome_Cancelled) _then;

/// Create a copy of BridgeTimelineAgentOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(BridgeTimelineAgentOutcome_Cancelled(
cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeTimelineContentOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineContentOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineContentOutcome()';
}


}

/// @nodoc
class $BridgeTimelineContentOutcomeCopyWith<$Res>  {
$BridgeTimelineContentOutcomeCopyWith(BridgeTimelineContentOutcome _, $Res Function(BridgeTimelineContentOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelineContentOutcome].
extension BridgeTimelineContentOutcomePatterns on BridgeTimelineContentOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineContentOutcome_Completed value)?  completed,TResult Function( BridgeTimelineContentOutcome_Failed value)?  failed,TResult Function( BridgeTimelineContentOutcome_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineContentOutcome_Completed() when completed != null:
return completed(_that);case BridgeTimelineContentOutcome_Failed() when failed != null:
return failed(_that);case BridgeTimelineContentOutcome_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineContentOutcome_Completed value)  completed,required TResult Function( BridgeTimelineContentOutcome_Failed value)  failed,required TResult Function( BridgeTimelineContentOutcome_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case BridgeTimelineContentOutcome_Completed():
return completed(_that);case BridgeTimelineContentOutcome_Failed():
return failed(_that);case BridgeTimelineContentOutcome_Cancelled():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineContentOutcome_Completed value)?  completed,TResult? Function( BridgeTimelineContentOutcome_Failed value)?  failed,TResult? Function( BridgeTimelineContentOutcome_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case BridgeTimelineContentOutcome_Completed() when completed != null:
return completed(_that);case BridgeTimelineContentOutcome_Failed() when failed != null:
return failed(_that);case BridgeTimelineContentOutcome_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PlatformInt64 completedAt)?  completed,TResult Function( PlatformInt64 failedAt,  String error)?  failed,TResult Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineContentOutcome_Completed() when completed != null:
return completed(_that.completedAt);case BridgeTimelineContentOutcome_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case BridgeTimelineContentOutcome_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PlatformInt64 completedAt)  completed,required TResult Function( PlatformInt64 failedAt,  String error)  failed,required TResult Function( PlatformInt64 cancelledAt,  String reason)  cancelled,}) {final _that = this;
switch (_that) {
case BridgeTimelineContentOutcome_Completed():
return completed(_that.completedAt);case BridgeTimelineContentOutcome_Failed():
return failed(_that.failedAt,_that.error);case BridgeTimelineContentOutcome_Cancelled():
return cancelled(_that.cancelledAt,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PlatformInt64 completedAt)?  completed,TResult? Function( PlatformInt64 failedAt,  String error)?  failed,TResult? Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,}) {final _that = this;
switch (_that) {
case BridgeTimelineContentOutcome_Completed() when completed != null:
return completed(_that.completedAt);case BridgeTimelineContentOutcome_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case BridgeTimelineContentOutcome_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineContentOutcome_Completed extends BridgeTimelineContentOutcome {
  const BridgeTimelineContentOutcome_Completed({required this.completedAt}): super._();


 final  PlatformInt64 completedAt;

/// Create a copy of BridgeTimelineContentOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineContentOutcome_CompletedCopyWith<BridgeTimelineContentOutcome_Completed> get copyWith => _$BridgeTimelineContentOutcome_CompletedCopyWithImpl<BridgeTimelineContentOutcome_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineContentOutcome_Completed&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt);
}

@override
String toString() {
    return 'BridgeTimelineContentOutcome.completed(completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineContentOutcome_CompletedCopyWith<$Res> implements $BridgeTimelineContentOutcomeCopyWith<$Res> {
  factory $BridgeTimelineContentOutcome_CompletedCopyWith(BridgeTimelineContentOutcome_Completed value, $Res Function(BridgeTimelineContentOutcome_Completed) _then) = _$BridgeTimelineContentOutcome_CompletedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 completedAt
});




}
/// @nodoc
class _$BridgeTimelineContentOutcome_CompletedCopyWithImpl<$Res>
    implements $BridgeTimelineContentOutcome_CompletedCopyWith<$Res> {
  _$BridgeTimelineContentOutcome_CompletedCopyWithImpl(this._self, this._then);

  final BridgeTimelineContentOutcome_Completed _self;
  final $Res Function(BridgeTimelineContentOutcome_Completed) _then;

/// Create a copy of BridgeTimelineContentOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,}) {
  return _then(BridgeTimelineContentOutcome_Completed(
completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeTimelineContentOutcome_Failed extends BridgeTimelineContentOutcome {
  const BridgeTimelineContentOutcome_Failed({required this.failedAt, required this.error}): super._();


 final  PlatformInt64 failedAt;
 final  String error;

/// Create a copy of BridgeTimelineContentOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineContentOutcome_FailedCopyWith<BridgeTimelineContentOutcome_Failed> get copyWith => _$BridgeTimelineContentOutcome_FailedCopyWithImpl<BridgeTimelineContentOutcome_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineContentOutcome_Failed&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,error);
}

@override
String toString() {
    return 'BridgeTimelineContentOutcome.failed(failedAt: $failedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineContentOutcome_FailedCopyWith<$Res> implements $BridgeTimelineContentOutcomeCopyWith<$Res> {
  factory $BridgeTimelineContentOutcome_FailedCopyWith(BridgeTimelineContentOutcome_Failed value, $Res Function(BridgeTimelineContentOutcome_Failed) _then) = _$BridgeTimelineContentOutcome_FailedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 failedAt, String error
});




}
/// @nodoc
class _$BridgeTimelineContentOutcome_FailedCopyWithImpl<$Res>
    implements $BridgeTimelineContentOutcome_FailedCopyWith<$Res> {
  _$BridgeTimelineContentOutcome_FailedCopyWithImpl(this._self, this._then);

  final BridgeTimelineContentOutcome_Failed _self;
  final $Res Function(BridgeTimelineContentOutcome_Failed) _then;

/// Create a copy of BridgeTimelineContentOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? error = null,}) {
  return _then(BridgeTimelineContentOutcome_Failed(
failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeTimelineContentOutcome_Cancelled extends BridgeTimelineContentOutcome {
  const BridgeTimelineContentOutcome_Cancelled({required this.cancelledAt, required this.reason}): super._();


 final  PlatformInt64 cancelledAt;
 final  String reason;

/// Create a copy of BridgeTimelineContentOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineContentOutcome_CancelledCopyWith<BridgeTimelineContentOutcome_Cancelled> get copyWith => _$BridgeTimelineContentOutcome_CancelledCopyWithImpl<BridgeTimelineContentOutcome_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineContentOutcome_Cancelled&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}

@override
String toString() {
    return 'BridgeTimelineContentOutcome.cancelled(cancelledAt: $cancelledAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineContentOutcome_CancelledCopyWith<$Res> implements $BridgeTimelineContentOutcomeCopyWith<$Res> {
  factory $BridgeTimelineContentOutcome_CancelledCopyWith(BridgeTimelineContentOutcome_Cancelled value, $Res Function(BridgeTimelineContentOutcome_Cancelled) _then) = _$BridgeTimelineContentOutcome_CancelledCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 cancelledAt, String reason
});




}
/// @nodoc
class _$BridgeTimelineContentOutcome_CancelledCopyWithImpl<$Res>
    implements $BridgeTimelineContentOutcome_CancelledCopyWith<$Res> {
  _$BridgeTimelineContentOutcome_CancelledCopyWithImpl(this._self, this._then);

  final BridgeTimelineContentOutcome_Cancelled _self;
  final $Res Function(BridgeTimelineContentOutcome_Cancelled) _then;

/// Create a copy of BridgeTimelineContentOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(BridgeTimelineContentOutcome_Cancelled(
cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeTimelineDescriptor {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineDescriptor()';
}


}

/// @nodoc
class $BridgeTimelineDescriptorCopyWith<$Res>  {
$BridgeTimelineDescriptorCopyWith(BridgeTimelineDescriptor _, $Res Function(BridgeTimelineDescriptor) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelineDescriptor].
extension BridgeTimelineDescriptorPatterns on BridgeTimelineDescriptor {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineDescriptor_Text value)?  text,TResult Function( BridgeTimelineDescriptor_Thinking value)?  thinking,TResult Function( BridgeTimelineDescriptor_Tool value)?  tool,TResult Function( BridgeTimelineDescriptor_Raw value)?  raw,TResult Function( BridgeTimelineDescriptor_Agent value)?  agent,TResult Function( BridgeTimelineDescriptor_Turn value)?  turn,TResult Function( BridgeTimelineDescriptor_Inference value)?  inference,TResult Function( BridgeTimelineDescriptor_Skill value)?  skill,TResult Function( BridgeTimelineDescriptor_File value)?  file,TResult Function( BridgeTimelineDescriptor_ContextCompaction value)?  contextCompaction,TResult Function( BridgeTimelineDescriptor_Plan value)?  plan,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text() when text != null:
return text(_that);case BridgeTimelineDescriptor_Thinking() when thinking != null:
return thinking(_that);case BridgeTimelineDescriptor_Tool() when tool != null:
return tool(_that);case BridgeTimelineDescriptor_Raw() when raw != null:
return raw(_that);case BridgeTimelineDescriptor_Agent() when agent != null:
return agent(_that);case BridgeTimelineDescriptor_Turn() when turn != null:
return turn(_that);case BridgeTimelineDescriptor_Inference() when inference != null:
return inference(_that);case BridgeTimelineDescriptor_Skill() when skill != null:
return skill(_that);case BridgeTimelineDescriptor_File() when file != null:
return file(_that);case BridgeTimelineDescriptor_ContextCompaction() when contextCompaction != null:
return contextCompaction(_that);case BridgeTimelineDescriptor_Plan() when plan != null:
return plan(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineDescriptor_Text value)  text,required TResult Function( BridgeTimelineDescriptor_Thinking value)  thinking,required TResult Function( BridgeTimelineDescriptor_Tool value)  tool,required TResult Function( BridgeTimelineDescriptor_Raw value)  raw,required TResult Function( BridgeTimelineDescriptor_Agent value)  agent,required TResult Function( BridgeTimelineDescriptor_Turn value)  turn,required TResult Function( BridgeTimelineDescriptor_Inference value)  inference,required TResult Function( BridgeTimelineDescriptor_Skill value)  skill,required TResult Function( BridgeTimelineDescriptor_File value)  file,required TResult Function( BridgeTimelineDescriptor_ContextCompaction value)  contextCompaction,required TResult Function( BridgeTimelineDescriptor_Plan value)  plan,}){
final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text():
return text(_that);case BridgeTimelineDescriptor_Thinking():
return thinking(_that);case BridgeTimelineDescriptor_Tool():
return tool(_that);case BridgeTimelineDescriptor_Raw():
return raw(_that);case BridgeTimelineDescriptor_Agent():
return agent(_that);case BridgeTimelineDescriptor_Turn():
return turn(_that);case BridgeTimelineDescriptor_Inference():
return inference(_that);case BridgeTimelineDescriptor_Skill():
return skill(_that);case BridgeTimelineDescriptor_File():
return file(_that);case BridgeTimelineDescriptor_ContextCompaction():
return contextCompaction(_that);case BridgeTimelineDescriptor_Plan():
return plan(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineDescriptor_Text value)?  text,TResult? Function( BridgeTimelineDescriptor_Thinking value)?  thinking,TResult? Function( BridgeTimelineDescriptor_Tool value)?  tool,TResult? Function( BridgeTimelineDescriptor_Raw value)?  raw,TResult? Function( BridgeTimelineDescriptor_Agent value)?  agent,TResult? Function( BridgeTimelineDescriptor_Turn value)?  turn,TResult? Function( BridgeTimelineDescriptor_Inference value)?  inference,TResult? Function( BridgeTimelineDescriptor_Skill value)?  skill,TResult? Function( BridgeTimelineDescriptor_File value)?  file,TResult? Function( BridgeTimelineDescriptor_ContextCompaction value)?  contextCompaction,TResult? Function( BridgeTimelineDescriptor_Plan value)?  plan,}){
final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text() when text != null:
return text(_that);case BridgeTimelineDescriptor_Thinking() when thinking != null:
return thinking(_that);case BridgeTimelineDescriptor_Tool() when tool != null:
return tool(_that);case BridgeTimelineDescriptor_Raw() when raw != null:
return raw(_that);case BridgeTimelineDescriptor_Agent() when agent != null:
return agent(_that);case BridgeTimelineDescriptor_Turn() when turn != null:
return turn(_that);case BridgeTimelineDescriptor_Inference() when inference != null:
return inference(_that);case BridgeTimelineDescriptor_Skill() when skill != null:
return skill(_that);case BridgeTimelineDescriptor_File() when file != null:
return file(_that);case BridgeTimelineDescriptor_ContextCompaction() when contextCompaction != null:
return contextCompaction(_that);case BridgeTimelineDescriptor_Plan() when plan != null:
return plan(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeTimelineTextDescriptor field0)?  text,TResult Function( BridgeTimelineThinkingDescriptor field0)?  thinking,TResult Function( BridgeTimelineToolDescriptor field0)?  tool,TResult Function( BridgeTimelineRawDescriptor field0)?  raw,TResult Function( BridgeThreadAgentIdentity identity,  BridgeTimelineAgentOutcome outcome)?  agent,TResult Function( BridgeTimelineTurnOutcome outcome,  String? inputId)?  turn,TResult Function( String inferenceId,  String model,  BridgeTimelineInferenceOutcome outcome)?  inference,TResult Function( String name,  String source,  String providerId,  BridgeSkillResourceBase resourceBase,  BridgeSkillActivationCause cause,  PlatformInt64 activatedAt)?  skill,TResult Function( String path,  String? mediaType,  PlatformInt64 completedAt)?  file,TResult Function( BigInt? beforeTokens,  BigInt? afterTokens,  PlatformInt64 compactedAt)?  contextCompaction,TResult Function( String interactionId,  BigInt? documentVersion,  String? contentHash,  BridgeTimelinePlanDecision decision)?  plan,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text() when text != null:
return text(_that.field0);case BridgeTimelineDescriptor_Thinking() when thinking != null:
return thinking(_that.field0);case BridgeTimelineDescriptor_Tool() when tool != null:
return tool(_that.field0);case BridgeTimelineDescriptor_Raw() when raw != null:
return raw(_that.field0);case BridgeTimelineDescriptor_Agent() when agent != null:
return agent(_that.identity,_that.outcome);case BridgeTimelineDescriptor_Turn() when turn != null:
return turn(_that.outcome,_that.inputId);case BridgeTimelineDescriptor_Inference() when inference != null:
return inference(_that.inferenceId,_that.model,_that.outcome);case BridgeTimelineDescriptor_Skill() when skill != null:
return skill(_that.name,_that.source,_that.providerId,_that.resourceBase,_that.cause,_that.activatedAt);case BridgeTimelineDescriptor_File() when file != null:
return file(_that.path,_that.mediaType,_that.completedAt);case BridgeTimelineDescriptor_ContextCompaction() when contextCompaction != null:
return contextCompaction(_that.beforeTokens,_that.afterTokens,_that.compactedAt);case BridgeTimelineDescriptor_Plan() when plan != null:
return plan(_that.interactionId,_that.documentVersion,_that.contentHash,_that.decision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeTimelineTextDescriptor field0)  text,required TResult Function( BridgeTimelineThinkingDescriptor field0)  thinking,required TResult Function( BridgeTimelineToolDescriptor field0)  tool,required TResult Function( BridgeTimelineRawDescriptor field0)  raw,required TResult Function( BridgeThreadAgentIdentity identity,  BridgeTimelineAgentOutcome outcome)  agent,required TResult Function( BridgeTimelineTurnOutcome outcome,  String? inputId)  turn,required TResult Function( String inferenceId,  String model,  BridgeTimelineInferenceOutcome outcome)  inference,required TResult Function( String name,  String source,  String providerId,  BridgeSkillResourceBase resourceBase,  BridgeSkillActivationCause cause,  PlatformInt64 activatedAt)  skill,required TResult Function( String path,  String? mediaType,  PlatformInt64 completedAt)  file,required TResult Function( BigInt? beforeTokens,  BigInt? afterTokens,  PlatformInt64 compactedAt)  contextCompaction,required TResult Function( String interactionId,  BigInt? documentVersion,  String? contentHash,  BridgeTimelinePlanDecision decision)  plan,}) {final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text():
return text(_that.field0);case BridgeTimelineDescriptor_Thinking():
return thinking(_that.field0);case BridgeTimelineDescriptor_Tool():
return tool(_that.field0);case BridgeTimelineDescriptor_Raw():
return raw(_that.field0);case BridgeTimelineDescriptor_Agent():
return agent(_that.identity,_that.outcome);case BridgeTimelineDescriptor_Turn():
return turn(_that.outcome,_that.inputId);case BridgeTimelineDescriptor_Inference():
return inference(_that.inferenceId,_that.model,_that.outcome);case BridgeTimelineDescriptor_Skill():
return skill(_that.name,_that.source,_that.providerId,_that.resourceBase,_that.cause,_that.activatedAt);case BridgeTimelineDescriptor_File():
return file(_that.path,_that.mediaType,_that.completedAt);case BridgeTimelineDescriptor_ContextCompaction():
return contextCompaction(_that.beforeTokens,_that.afterTokens,_that.compactedAt);case BridgeTimelineDescriptor_Plan():
return plan(_that.interactionId,_that.documentVersion,_that.contentHash,_that.decision);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineTextDescriptor field0)?  text,TResult? Function( BridgeTimelineThinkingDescriptor field0)?  thinking,TResult? Function( BridgeTimelineToolDescriptor field0)?  tool,TResult? Function( BridgeTimelineRawDescriptor field0)?  raw,TResult? Function( BridgeThreadAgentIdentity identity,  BridgeTimelineAgentOutcome outcome)?  agent,TResult? Function( BridgeTimelineTurnOutcome outcome,  String? inputId)?  turn,TResult? Function( String inferenceId,  String model,  BridgeTimelineInferenceOutcome outcome)?  inference,TResult? Function( String name,  String source,  String providerId,  BridgeSkillResourceBase resourceBase,  BridgeSkillActivationCause cause,  PlatformInt64 activatedAt)?  skill,TResult? Function( String path,  String? mediaType,  PlatformInt64 completedAt)?  file,TResult? Function( BigInt? beforeTokens,  BigInt? afterTokens,  PlatformInt64 compactedAt)?  contextCompaction,TResult? Function( String interactionId,  BigInt? documentVersion,  String? contentHash,  BridgeTimelinePlanDecision decision)?  plan,}) {final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text() when text != null:
return text(_that.field0);case BridgeTimelineDescriptor_Thinking() when thinking != null:
return thinking(_that.field0);case BridgeTimelineDescriptor_Tool() when tool != null:
return tool(_that.field0);case BridgeTimelineDescriptor_Raw() when raw != null:
return raw(_that.field0);case BridgeTimelineDescriptor_Agent() when agent != null:
return agent(_that.identity,_that.outcome);case BridgeTimelineDescriptor_Turn() when turn != null:
return turn(_that.outcome,_that.inputId);case BridgeTimelineDescriptor_Inference() when inference != null:
return inference(_that.inferenceId,_that.model,_that.outcome);case BridgeTimelineDescriptor_Skill() when skill != null:
return skill(_that.name,_that.source,_that.providerId,_that.resourceBase,_that.cause,_that.activatedAt);case BridgeTimelineDescriptor_File() when file != null:
return file(_that.path,_that.mediaType,_that.completedAt);case BridgeTimelineDescriptor_ContextCompaction() when contextCompaction != null:
return contextCompaction(_that.beforeTokens,_that.afterTokens,_that.compactedAt);case BridgeTimelineDescriptor_Plan() when plan != null:
return plan(_that.interactionId,_that.documentVersion,_that.contentHash,_that.decision);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineDescriptor_Text extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Text(this.field0): super._();


 final  BridgeTimelineTextDescriptor field0;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_TextCopyWith<BridgeTimelineDescriptor_Text> get copyWith => _$BridgeTimelineDescriptor_TextCopyWithImpl<BridgeTimelineDescriptor_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Text&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.text(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_TextCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_TextCopyWith(BridgeTimelineDescriptor_Text value, $Res Function(BridgeTimelineDescriptor_Text) _then) = _$BridgeTimelineDescriptor_TextCopyWithImpl;
@useResult
$Res call({
 BridgeTimelineTextDescriptor field0
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_TextCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_TextCopyWith<$Res> {
  _$BridgeTimelineDescriptor_TextCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Text _self;
  final $Res Function(BridgeTimelineDescriptor_Text) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeTimelineDescriptor_Text(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeTimelineTextDescriptor,
  ));
}


}

/// @nodoc


class BridgeTimelineDescriptor_Thinking extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Thinking(this.field0): super._();


 final  BridgeTimelineThinkingDescriptor field0;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_ThinkingCopyWith<BridgeTimelineDescriptor_Thinking> get copyWith => _$BridgeTimelineDescriptor_ThinkingCopyWithImpl<BridgeTimelineDescriptor_Thinking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Thinking&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.thinking(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_ThinkingCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_ThinkingCopyWith(BridgeTimelineDescriptor_Thinking value, $Res Function(BridgeTimelineDescriptor_Thinking) _then) = _$BridgeTimelineDescriptor_ThinkingCopyWithImpl;
@useResult
$Res call({
 BridgeTimelineThinkingDescriptor field0
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_ThinkingCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_ThinkingCopyWith<$Res> {
  _$BridgeTimelineDescriptor_ThinkingCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Thinking _self;
  final $Res Function(BridgeTimelineDescriptor_Thinking) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeTimelineDescriptor_Thinking(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeTimelineThinkingDescriptor,
  ));
}


}

/// @nodoc


class BridgeTimelineDescriptor_Tool extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Tool(this.field0): super._();


 final  BridgeTimelineToolDescriptor field0;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_ToolCopyWith<BridgeTimelineDescriptor_Tool> get copyWith => _$BridgeTimelineDescriptor_ToolCopyWithImpl<BridgeTimelineDescriptor_Tool>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Tool&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.tool(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_ToolCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_ToolCopyWith(BridgeTimelineDescriptor_Tool value, $Res Function(BridgeTimelineDescriptor_Tool) _then) = _$BridgeTimelineDescriptor_ToolCopyWithImpl;
@useResult
$Res call({
 BridgeTimelineToolDescriptor field0
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_ToolCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_ToolCopyWith<$Res> {
  _$BridgeTimelineDescriptor_ToolCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Tool _self;
  final $Res Function(BridgeTimelineDescriptor_Tool) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeTimelineDescriptor_Tool(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeTimelineToolDescriptor,
  ));
}


}

/// @nodoc


class BridgeTimelineDescriptor_Raw extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Raw(this.field0): super._();


 final  BridgeTimelineRawDescriptor field0;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_RawCopyWith<BridgeTimelineDescriptor_Raw> get copyWith => _$BridgeTimelineDescriptor_RawCopyWithImpl<BridgeTimelineDescriptor_Raw>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Raw&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.raw(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_RawCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_RawCopyWith(BridgeTimelineDescriptor_Raw value, $Res Function(BridgeTimelineDescriptor_Raw) _then) = _$BridgeTimelineDescriptor_RawCopyWithImpl;
@useResult
$Res call({
 BridgeTimelineRawDescriptor field0
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_RawCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_RawCopyWith<$Res> {
  _$BridgeTimelineDescriptor_RawCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Raw _self;
  final $Res Function(BridgeTimelineDescriptor_Raw) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeTimelineDescriptor_Raw(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeTimelineRawDescriptor,
  ));
}


}

/// @nodoc


class BridgeTimelineDescriptor_Agent extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Agent({required this.identity, required this.outcome}): super._();


 final  BridgeThreadAgentIdentity identity;
 final  BridgeTimelineAgentOutcome outcome;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_AgentCopyWith<BridgeTimelineDescriptor_Agent> get copyWith => _$BridgeTimelineDescriptor_AgentCopyWithImpl<BridgeTimelineDescriptor_Agent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Agent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.outcome, outcome) || other.outcome == outcome));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,outcome);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.agent(identity: $identity, outcome: $outcome)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_AgentCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_AgentCopyWith(BridgeTimelineDescriptor_Agent value, $Res Function(BridgeTimelineDescriptor_Agent) _then) = _$BridgeTimelineDescriptor_AgentCopyWithImpl;
@useResult
$Res call({
 BridgeThreadAgentIdentity identity, BridgeTimelineAgentOutcome outcome
});


$BridgeTimelineAgentOutcomeCopyWith<$Res> get outcome;

}
/// @nodoc
class _$BridgeTimelineDescriptor_AgentCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_AgentCopyWith<$Res> {
  _$BridgeTimelineDescriptor_AgentCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Agent _self;
  final $Res Function(BridgeTimelineDescriptor_Agent) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? outcome = null,}) {
  return _then(BridgeTimelineDescriptor_Agent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadAgentIdentity,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as BridgeTimelineAgentOutcome,
  ));
}

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeTimelineAgentOutcomeCopyWith<$Res> get outcome {

  return $BridgeTimelineAgentOutcomeCopyWith<$Res>(_self.outcome, (value) {
    return _then(_self.copyWith(outcome: value));
  });
}
}

/// @nodoc


class BridgeTimelineDescriptor_Turn extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Turn({required this.outcome, this.inputId}): super._();


 final  BridgeTimelineTurnOutcome outcome;
 final  String? inputId;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_TurnCopyWith<BridgeTimelineDescriptor_Turn> get copyWith => _$BridgeTimelineDescriptor_TurnCopyWithImpl<BridgeTimelineDescriptor_Turn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Turn&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.inputId, inputId) || other.inputId == inputId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,outcome,inputId);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.turn(outcome: $outcome, inputId: $inputId)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_TurnCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_TurnCopyWith(BridgeTimelineDescriptor_Turn value, $Res Function(BridgeTimelineDescriptor_Turn) _then) = _$BridgeTimelineDescriptor_TurnCopyWithImpl;
@useResult
$Res call({
 BridgeTimelineTurnOutcome outcome, String? inputId
});


$BridgeTimelineTurnOutcomeCopyWith<$Res> get outcome;

}
/// @nodoc
class _$BridgeTimelineDescriptor_TurnCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_TurnCopyWith<$Res> {
  _$BridgeTimelineDescriptor_TurnCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Turn _self;
  final $Res Function(BridgeTimelineDescriptor_Turn) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? outcome = null,Object? inputId = freezed,}) {
  return _then(BridgeTimelineDescriptor_Turn(
outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as BridgeTimelineTurnOutcome,inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeTimelineTurnOutcomeCopyWith<$Res> get outcome {

  return $BridgeTimelineTurnOutcomeCopyWith<$Res>(_self.outcome, (value) {
    return _then(_self.copyWith(outcome: value));
  });
}
}

/// @nodoc


class BridgeTimelineDescriptor_Inference extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Inference({required this.inferenceId, required this.model, required this.outcome}): super._();


 final  String inferenceId;
 final  String model;
 final  BridgeTimelineInferenceOutcome outcome;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_InferenceCopyWith<BridgeTimelineDescriptor_Inference> get copyWith => _$BridgeTimelineDescriptor_InferenceCopyWithImpl<BridgeTimelineDescriptor_Inference>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Inference&&(identical(other.inferenceId, inferenceId) || other.inferenceId == inferenceId)&&(identical(other.model, model) || other.model == model)&&(identical(other.outcome, outcome) || other.outcome == outcome));
}


@override
int get hashCode {
    return Object.hash(runtimeType,inferenceId,model,outcome);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.inference(inferenceId: $inferenceId, model: $model, outcome: $outcome)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_InferenceCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_InferenceCopyWith(BridgeTimelineDescriptor_Inference value, $Res Function(BridgeTimelineDescriptor_Inference) _then) = _$BridgeTimelineDescriptor_InferenceCopyWithImpl;
@useResult
$Res call({
 String inferenceId, String model, BridgeTimelineInferenceOutcome outcome
});


$BridgeTimelineInferenceOutcomeCopyWith<$Res> get outcome;

}
/// @nodoc
class _$BridgeTimelineDescriptor_InferenceCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_InferenceCopyWith<$Res> {
  _$BridgeTimelineDescriptor_InferenceCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Inference _self;
  final $Res Function(BridgeTimelineDescriptor_Inference) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? inferenceId = null,Object? model = null,Object? outcome = null,}) {
  return _then(BridgeTimelineDescriptor_Inference(
inferenceId: null == inferenceId ? _self.inferenceId : inferenceId // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as BridgeTimelineInferenceOutcome,
  ));
}

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeTimelineInferenceOutcomeCopyWith<$Res> get outcome {

  return $BridgeTimelineInferenceOutcomeCopyWith<$Res>(_self.outcome, (value) {
    return _then(_self.copyWith(outcome: value));
  });
}
}

/// @nodoc


class BridgeTimelineDescriptor_Skill extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Skill({required this.name, required this.source, required this.providerId, required this.resourceBase, required this.cause, required this.activatedAt}): super._();


 final  String name;
 final  String source;
 final  String providerId;
 final  BridgeSkillResourceBase resourceBase;
 final  BridgeSkillActivationCause cause;
 final  PlatformInt64 activatedAt;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_SkillCopyWith<BridgeTimelineDescriptor_Skill> get copyWith => _$BridgeTimelineDescriptor_SkillCopyWithImpl<BridgeTimelineDescriptor_Skill>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Skill&&(identical(other.name, name) || other.name == name)&&(identical(other.source, source) || other.source == source)&&(identical(other.providerId, providerId) || other.providerId == providerId)&&(identical(other.resourceBase, resourceBase) || other.resourceBase == resourceBase)&&(identical(other.cause, cause) || other.cause == cause)&&(identical(other.activatedAt, activatedAt) || other.activatedAt == activatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,source,providerId,resourceBase,cause,activatedAt);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.skill(name: $name, source: $source, providerId: $providerId, resourceBase: $resourceBase, cause: $cause, activatedAt: $activatedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_SkillCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_SkillCopyWith(BridgeTimelineDescriptor_Skill value, $Res Function(BridgeTimelineDescriptor_Skill) _then) = _$BridgeTimelineDescriptor_SkillCopyWithImpl;
@useResult
$Res call({
 String name, String source, String providerId, BridgeSkillResourceBase resourceBase, BridgeSkillActivationCause cause, PlatformInt64 activatedAt
});


$BridgeSkillResourceBaseCopyWith<$Res> get resourceBase;$BridgeSkillActivationCauseCopyWith<$Res> get cause;

}
/// @nodoc
class _$BridgeTimelineDescriptor_SkillCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_SkillCopyWith<$Res> {
  _$BridgeTimelineDescriptor_SkillCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Skill _self;
  final $Res Function(BridgeTimelineDescriptor_Skill) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? source = null,Object? providerId = null,Object? resourceBase = null,Object? cause = null,Object? activatedAt = null,}) {
  return _then(BridgeTimelineDescriptor_Skill(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,providerId: null == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as String,resourceBase: null == resourceBase ? _self.resourceBase : resourceBase // ignore: cast_nullable_to_non_nullable
as BridgeSkillResourceBase,cause: null == cause ? _self.cause : cause // ignore: cast_nullable_to_non_nullable
as BridgeSkillActivationCause,activatedAt: null == activatedAt ? _self.activatedAt : activatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeSkillResourceBaseCopyWith<$Res> get resourceBase {

  return $BridgeSkillResourceBaseCopyWith<$Res>(_self.resourceBase, (value) {
    return _then(_self.copyWith(resourceBase: value));
  });
}/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeSkillActivationCauseCopyWith<$Res> get cause {

  return $BridgeSkillActivationCauseCopyWith<$Res>(_self.cause, (value) {
    return _then(_self.copyWith(cause: value));
  });
}
}

/// @nodoc


class BridgeTimelineDescriptor_File extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_File({required this.path, this.mediaType, required this.completedAt}): super._();


 final  String path;
 final  String? mediaType;
 final  PlatformInt64 completedAt;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_FileCopyWith<BridgeTimelineDescriptor_File> get copyWith => _$BridgeTimelineDescriptor_FileCopyWithImpl<BridgeTimelineDescriptor_File>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_File&&(identical(other.path, path) || other.path == path)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path,mediaType,completedAt);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.file(path: $path, mediaType: $mediaType, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_FileCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_FileCopyWith(BridgeTimelineDescriptor_File value, $Res Function(BridgeTimelineDescriptor_File) _then) = _$BridgeTimelineDescriptor_FileCopyWithImpl;
@useResult
$Res call({
 String path, String? mediaType, PlatformInt64 completedAt
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_FileCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_FileCopyWith<$Res> {
  _$BridgeTimelineDescriptor_FileCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_File _self;
  final $Res Function(BridgeTimelineDescriptor_File) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,Object? mediaType = freezed,Object? completedAt = null,}) {
  return _then(BridgeTimelineDescriptor_File(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,mediaType: freezed == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeTimelineDescriptor_ContextCompaction extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_ContextCompaction({this.beforeTokens, this.afterTokens, required this.compactedAt}): super._();


 final  BigInt? beforeTokens;
 final  BigInt? afterTokens;
 final  PlatformInt64 compactedAt;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_ContextCompactionCopyWith<BridgeTimelineDescriptor_ContextCompaction> get copyWith => _$BridgeTimelineDescriptor_ContextCompactionCopyWithImpl<BridgeTimelineDescriptor_ContextCompaction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_ContextCompaction&&(identical(other.beforeTokens, beforeTokens) || other.beforeTokens == beforeTokens)&&(identical(other.afterTokens, afterTokens) || other.afterTokens == afterTokens)&&(identical(other.compactedAt, compactedAt) || other.compactedAt == compactedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,beforeTokens,afterTokens,compactedAt);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.contextCompaction(beforeTokens: $beforeTokens, afterTokens: $afterTokens, compactedAt: $compactedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_ContextCompactionCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_ContextCompactionCopyWith(BridgeTimelineDescriptor_ContextCompaction value, $Res Function(BridgeTimelineDescriptor_ContextCompaction) _then) = _$BridgeTimelineDescriptor_ContextCompactionCopyWithImpl;
@useResult
$Res call({
 BigInt? beforeTokens, BigInt? afterTokens, PlatformInt64 compactedAt
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_ContextCompactionCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_ContextCompactionCopyWith<$Res> {
  _$BridgeTimelineDescriptor_ContextCompactionCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_ContextCompaction _self;
  final $Res Function(BridgeTimelineDescriptor_ContextCompaction) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? beforeTokens = freezed,Object? afterTokens = freezed,Object? compactedAt = null,}) {
  return _then(BridgeTimelineDescriptor_ContextCompaction(
beforeTokens: freezed == beforeTokens ? _self.beforeTokens : beforeTokens // ignore: cast_nullable_to_non_nullable
as BigInt?,afterTokens: freezed == afterTokens ? _self.afterTokens : afterTokens // ignore: cast_nullable_to_non_nullable
as BigInt?,compactedAt: null == compactedAt ? _self.compactedAt : compactedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeTimelineDescriptor_Plan extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Plan({required this.interactionId, this.documentVersion, this.contentHash, required this.decision}): super._();


 final  String interactionId;
 final  BigInt? documentVersion;
 final  String? contentHash;
 final  BridgeTimelinePlanDecision decision;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_PlanCopyWith<BridgeTimelineDescriptor_Plan> get copyWith => _$BridgeTimelineDescriptor_PlanCopyWithImpl<BridgeTimelineDescriptor_Plan>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Plan&&(identical(other.interactionId, interactionId) || other.interactionId == interactionId)&&(identical(other.documentVersion, documentVersion) || other.documentVersion == documentVersion)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.decision, decision) || other.decision == decision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,interactionId,documentVersion,contentHash,decision);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.plan(interactionId: $interactionId, documentVersion: $documentVersion, contentHash: $contentHash, decision: $decision)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_PlanCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_PlanCopyWith(BridgeTimelineDescriptor_Plan value, $Res Function(BridgeTimelineDescriptor_Plan) _then) = _$BridgeTimelineDescriptor_PlanCopyWithImpl;
@useResult
$Res call({
 String interactionId, BigInt? documentVersion, String? contentHash, BridgeTimelinePlanDecision decision
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_PlanCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_PlanCopyWith<$Res> {
  _$BridgeTimelineDescriptor_PlanCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Plan _self;
  final $Res Function(BridgeTimelineDescriptor_Plan) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? interactionId = null,Object? documentVersion = freezed,Object? contentHash = freezed,Object? decision = null,}) {
  return _then(BridgeTimelineDescriptor_Plan(
interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as String,documentVersion: freezed == documentVersion ? _self.documentVersion : documentVersion // ignore: cast_nullable_to_non_nullable
as BigInt?,contentHash: freezed == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String?,decision: null == decision ? _self.decision : decision // ignore: cast_nullable_to_non_nullable
as BridgeTimelinePlanDecision,
  ));
}


}

/// @nodoc
mixin _$BridgeTimelineInferenceOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineInferenceOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineInferenceOutcome()';
}


}

/// @nodoc
class $BridgeTimelineInferenceOutcomeCopyWith<$Res>  {
$BridgeTimelineInferenceOutcomeCopyWith(BridgeTimelineInferenceOutcome _, $Res Function(BridgeTimelineInferenceOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelineInferenceOutcome].
extension BridgeTimelineInferenceOutcomePatterns on BridgeTimelineInferenceOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineInferenceOutcome_Completed value)?  completed,TResult Function( BridgeTimelineInferenceOutcome_Failed value)?  failed,TResult Function( BridgeTimelineInferenceOutcome_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineInferenceOutcome_Completed() when completed != null:
return completed(_that);case BridgeTimelineInferenceOutcome_Failed() when failed != null:
return failed(_that);case BridgeTimelineInferenceOutcome_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineInferenceOutcome_Completed value)  completed,required TResult Function( BridgeTimelineInferenceOutcome_Failed value)  failed,required TResult Function( BridgeTimelineInferenceOutcome_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case BridgeTimelineInferenceOutcome_Completed():
return completed(_that);case BridgeTimelineInferenceOutcome_Failed():
return failed(_that);case BridgeTimelineInferenceOutcome_Cancelled():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineInferenceOutcome_Completed value)?  completed,TResult? Function( BridgeTimelineInferenceOutcome_Failed value)?  failed,TResult? Function( BridgeTimelineInferenceOutcome_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case BridgeTimelineInferenceOutcome_Completed() when completed != null:
return completed(_that);case BridgeTimelineInferenceOutcome_Failed() when failed != null:
return failed(_that);case BridgeTimelineInferenceOutcome_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PlatformInt64 completedAt,  BridgeTokenUsageSnapshot usage)?  completed,TResult Function( PlatformInt64 failedAt,  String error)?  failed,TResult Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineInferenceOutcome_Completed() when completed != null:
return completed(_that.completedAt,_that.usage);case BridgeTimelineInferenceOutcome_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case BridgeTimelineInferenceOutcome_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PlatformInt64 completedAt,  BridgeTokenUsageSnapshot usage)  completed,required TResult Function( PlatformInt64 failedAt,  String error)  failed,required TResult Function( PlatformInt64 cancelledAt,  String reason)  cancelled,}) {final _that = this;
switch (_that) {
case BridgeTimelineInferenceOutcome_Completed():
return completed(_that.completedAt,_that.usage);case BridgeTimelineInferenceOutcome_Failed():
return failed(_that.failedAt,_that.error);case BridgeTimelineInferenceOutcome_Cancelled():
return cancelled(_that.cancelledAt,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PlatformInt64 completedAt,  BridgeTokenUsageSnapshot usage)?  completed,TResult? Function( PlatformInt64 failedAt,  String error)?  failed,TResult? Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,}) {final _that = this;
switch (_that) {
case BridgeTimelineInferenceOutcome_Completed() when completed != null:
return completed(_that.completedAt,_that.usage);case BridgeTimelineInferenceOutcome_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case BridgeTimelineInferenceOutcome_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineInferenceOutcome_Completed extends BridgeTimelineInferenceOutcome {
  const BridgeTimelineInferenceOutcome_Completed({required this.completedAt, required this.usage}): super._();


 final  PlatformInt64 completedAt;
 final  BridgeTokenUsageSnapshot usage;

/// Create a copy of BridgeTimelineInferenceOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineInferenceOutcome_CompletedCopyWith<BridgeTimelineInferenceOutcome_Completed> get copyWith => _$BridgeTimelineInferenceOutcome_CompletedCopyWithImpl<BridgeTimelineInferenceOutcome_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineInferenceOutcome_Completed&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.usage, usage) || other.usage == usage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt,usage);
}

@override
String toString() {
    return 'BridgeTimelineInferenceOutcome.completed(completedAt: $completedAt, usage: $usage)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineInferenceOutcome_CompletedCopyWith<$Res> implements $BridgeTimelineInferenceOutcomeCopyWith<$Res> {
  factory $BridgeTimelineInferenceOutcome_CompletedCopyWith(BridgeTimelineInferenceOutcome_Completed value, $Res Function(BridgeTimelineInferenceOutcome_Completed) _then) = _$BridgeTimelineInferenceOutcome_CompletedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 completedAt, BridgeTokenUsageSnapshot usage
});




}
/// @nodoc
class _$BridgeTimelineInferenceOutcome_CompletedCopyWithImpl<$Res>
    implements $BridgeTimelineInferenceOutcome_CompletedCopyWith<$Res> {
  _$BridgeTimelineInferenceOutcome_CompletedCopyWithImpl(this._self, this._then);

  final BridgeTimelineInferenceOutcome_Completed _self;
  final $Res Function(BridgeTimelineInferenceOutcome_Completed) _then;

/// Create a copy of BridgeTimelineInferenceOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,Object? usage = null,}) {
  return _then(BridgeTimelineInferenceOutcome_Completed(
completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,usage: null == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as BridgeTokenUsageSnapshot,
  ));
}


}

/// @nodoc


class BridgeTimelineInferenceOutcome_Failed extends BridgeTimelineInferenceOutcome {
  const BridgeTimelineInferenceOutcome_Failed({required this.failedAt, required this.error}): super._();


 final  PlatformInt64 failedAt;
 final  String error;

/// Create a copy of BridgeTimelineInferenceOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineInferenceOutcome_FailedCopyWith<BridgeTimelineInferenceOutcome_Failed> get copyWith => _$BridgeTimelineInferenceOutcome_FailedCopyWithImpl<BridgeTimelineInferenceOutcome_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineInferenceOutcome_Failed&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,error);
}

@override
String toString() {
    return 'BridgeTimelineInferenceOutcome.failed(failedAt: $failedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineInferenceOutcome_FailedCopyWith<$Res> implements $BridgeTimelineInferenceOutcomeCopyWith<$Res> {
  factory $BridgeTimelineInferenceOutcome_FailedCopyWith(BridgeTimelineInferenceOutcome_Failed value, $Res Function(BridgeTimelineInferenceOutcome_Failed) _then) = _$BridgeTimelineInferenceOutcome_FailedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 failedAt, String error
});




}
/// @nodoc
class _$BridgeTimelineInferenceOutcome_FailedCopyWithImpl<$Res>
    implements $BridgeTimelineInferenceOutcome_FailedCopyWith<$Res> {
  _$BridgeTimelineInferenceOutcome_FailedCopyWithImpl(this._self, this._then);

  final BridgeTimelineInferenceOutcome_Failed _self;
  final $Res Function(BridgeTimelineInferenceOutcome_Failed) _then;

/// Create a copy of BridgeTimelineInferenceOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? error = null,}) {
  return _then(BridgeTimelineInferenceOutcome_Failed(
failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeTimelineInferenceOutcome_Cancelled extends BridgeTimelineInferenceOutcome {
  const BridgeTimelineInferenceOutcome_Cancelled({required this.cancelledAt, required this.reason}): super._();


 final  PlatformInt64 cancelledAt;
 final  String reason;

/// Create a copy of BridgeTimelineInferenceOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineInferenceOutcome_CancelledCopyWith<BridgeTimelineInferenceOutcome_Cancelled> get copyWith => _$BridgeTimelineInferenceOutcome_CancelledCopyWithImpl<BridgeTimelineInferenceOutcome_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineInferenceOutcome_Cancelled&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}

@override
String toString() {
    return 'BridgeTimelineInferenceOutcome.cancelled(cancelledAt: $cancelledAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineInferenceOutcome_CancelledCopyWith<$Res> implements $BridgeTimelineInferenceOutcomeCopyWith<$Res> {
  factory $BridgeTimelineInferenceOutcome_CancelledCopyWith(BridgeTimelineInferenceOutcome_Cancelled value, $Res Function(BridgeTimelineInferenceOutcome_Cancelled) _then) = _$BridgeTimelineInferenceOutcome_CancelledCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 cancelledAt, String reason
});




}
/// @nodoc
class _$BridgeTimelineInferenceOutcome_CancelledCopyWithImpl<$Res>
    implements $BridgeTimelineInferenceOutcome_CancelledCopyWith<$Res> {
  _$BridgeTimelineInferenceOutcome_CancelledCopyWithImpl(this._self, this._then);

  final BridgeTimelineInferenceOutcome_Cancelled _self;
  final $Res Function(BridgeTimelineInferenceOutcome_Cancelled) _then;

/// Create a copy of BridgeTimelineInferenceOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(BridgeTimelineInferenceOutcome_Cancelled(
cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeTimelineToolState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineToolState()';
}


}

/// @nodoc
class $BridgeTimelineToolStateCopyWith<$Res>  {
$BridgeTimelineToolStateCopyWith(BridgeTimelineToolState _, $Res Function(BridgeTimelineToolState) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelineToolState].
extension BridgeTimelineToolStatePatterns on BridgeTimelineToolState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineToolState_BackgroundStarted value)?  backgroundStarted,TResult Function( BridgeTimelineToolState_Interrupted value)?  interrupted,TResult Function( BridgeTimelineToolState_Succeeded value)?  succeeded,TResult Function( BridgeTimelineToolState_Failed value)?  failed,TResult Function( BridgeTimelineToolState_Denied value)?  denied,TResult Function( BridgeTimelineToolState_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineToolState_BackgroundStarted() when backgroundStarted != null:
return backgroundStarted(_that);case BridgeTimelineToolState_Interrupted() when interrupted != null:
return interrupted(_that);case BridgeTimelineToolState_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeTimelineToolState_Failed() when failed != null:
return failed(_that);case BridgeTimelineToolState_Denied() when denied != null:
return denied(_that);case BridgeTimelineToolState_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineToolState_BackgroundStarted value)  backgroundStarted,required TResult Function( BridgeTimelineToolState_Interrupted value)  interrupted,required TResult Function( BridgeTimelineToolState_Succeeded value)  succeeded,required TResult Function( BridgeTimelineToolState_Failed value)  failed,required TResult Function( BridgeTimelineToolState_Denied value)  denied,required TResult Function( BridgeTimelineToolState_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case BridgeTimelineToolState_BackgroundStarted():
return backgroundStarted(_that);case BridgeTimelineToolState_Interrupted():
return interrupted(_that);case BridgeTimelineToolState_Succeeded():
return succeeded(_that);case BridgeTimelineToolState_Failed():
return failed(_that);case BridgeTimelineToolState_Denied():
return denied(_that);case BridgeTimelineToolState_Cancelled():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineToolState_BackgroundStarted value)?  backgroundStarted,TResult? Function( BridgeTimelineToolState_Interrupted value)?  interrupted,TResult? Function( BridgeTimelineToolState_Succeeded value)?  succeeded,TResult? Function( BridgeTimelineToolState_Failed value)?  failed,TResult? Function( BridgeTimelineToolState_Denied value)?  denied,TResult? Function( BridgeTimelineToolState_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case BridgeTimelineToolState_BackgroundStarted() when backgroundStarted != null:
return backgroundStarted(_that);case BridgeTimelineToolState_Interrupted() when interrupted != null:
return interrupted(_that);case BridgeTimelineToolState_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeTimelineToolState_Failed() when failed != null:
return failed(_that);case BridgeTimelineToolState_Denied() when denied != null:
return denied(_that);case BridgeTimelineToolState_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PlatformInt64 startedAt)?  backgroundStarted,TResult Function( PlatformInt64 interruptedAt,  String reason)?  interrupted,TResult Function( PlatformInt64 completedAt,  BridgeTimelineToolOutputDescriptor output)?  succeeded,TResult Function( PlatformInt64 failedAt,  BridgeThreadToolFailure failure,  BridgeTimelineToolOutputDescriptor? output)?  failed,TResult Function( PlatformInt64 deniedAt,  String reason)?  denied,TResult Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineToolState_BackgroundStarted() when backgroundStarted != null:
return backgroundStarted(_that.startedAt);case BridgeTimelineToolState_Interrupted() when interrupted != null:
return interrupted(_that.interruptedAt,_that.reason);case BridgeTimelineToolState_Succeeded() when succeeded != null:
return succeeded(_that.completedAt,_that.output);case BridgeTimelineToolState_Failed() when failed != null:
return failed(_that.failedAt,_that.failure,_that.output);case BridgeTimelineToolState_Denied() when denied != null:
return denied(_that.deniedAt,_that.reason);case BridgeTimelineToolState_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PlatformInt64 startedAt)  backgroundStarted,required TResult Function( PlatformInt64 interruptedAt,  String reason)  interrupted,required TResult Function( PlatformInt64 completedAt,  BridgeTimelineToolOutputDescriptor output)  succeeded,required TResult Function( PlatformInt64 failedAt,  BridgeThreadToolFailure failure,  BridgeTimelineToolOutputDescriptor? output)  failed,required TResult Function( PlatformInt64 deniedAt,  String reason)  denied,required TResult Function( PlatformInt64 cancelledAt,  String reason)  cancelled,}) {final _that = this;
switch (_that) {
case BridgeTimelineToolState_BackgroundStarted():
return backgroundStarted(_that.startedAt);case BridgeTimelineToolState_Interrupted():
return interrupted(_that.interruptedAt,_that.reason);case BridgeTimelineToolState_Succeeded():
return succeeded(_that.completedAt,_that.output);case BridgeTimelineToolState_Failed():
return failed(_that.failedAt,_that.failure,_that.output);case BridgeTimelineToolState_Denied():
return denied(_that.deniedAt,_that.reason);case BridgeTimelineToolState_Cancelled():
return cancelled(_that.cancelledAt,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PlatformInt64 startedAt)?  backgroundStarted,TResult? Function( PlatformInt64 interruptedAt,  String reason)?  interrupted,TResult? Function( PlatformInt64 completedAt,  BridgeTimelineToolOutputDescriptor output)?  succeeded,TResult? Function( PlatformInt64 failedAt,  BridgeThreadToolFailure failure,  BridgeTimelineToolOutputDescriptor? output)?  failed,TResult? Function( PlatformInt64 deniedAt,  String reason)?  denied,TResult? Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,}) {final _that = this;
switch (_that) {
case BridgeTimelineToolState_BackgroundStarted() when backgroundStarted != null:
return backgroundStarted(_that.startedAt);case BridgeTimelineToolState_Interrupted() when interrupted != null:
return interrupted(_that.interruptedAt,_that.reason);case BridgeTimelineToolState_Succeeded() when succeeded != null:
return succeeded(_that.completedAt,_that.output);case BridgeTimelineToolState_Failed() when failed != null:
return failed(_that.failedAt,_that.failure,_that.output);case BridgeTimelineToolState_Denied() when denied != null:
return denied(_that.deniedAt,_that.reason);case BridgeTimelineToolState_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineToolState_BackgroundStarted extends BridgeTimelineToolState {
  const BridgeTimelineToolState_BackgroundStarted({required this.startedAt}): super._();


 final  PlatformInt64 startedAt;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineToolState_BackgroundStartedCopyWith<BridgeTimelineToolState_BackgroundStarted> get copyWith => _$BridgeTimelineToolState_BackgroundStartedCopyWithImpl<BridgeTimelineToolState_BackgroundStarted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_BackgroundStarted&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt);
}

@override
String toString() {
    return 'BridgeTimelineToolState.backgroundStarted(startedAt: $startedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineToolState_BackgroundStartedCopyWith<$Res> implements $BridgeTimelineToolStateCopyWith<$Res> {
  factory $BridgeTimelineToolState_BackgroundStartedCopyWith(BridgeTimelineToolState_BackgroundStarted value, $Res Function(BridgeTimelineToolState_BackgroundStarted) _then) = _$BridgeTimelineToolState_BackgroundStartedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 startedAt
});




}
/// @nodoc
class _$BridgeTimelineToolState_BackgroundStartedCopyWithImpl<$Res>
    implements $BridgeTimelineToolState_BackgroundStartedCopyWith<$Res> {
  _$BridgeTimelineToolState_BackgroundStartedCopyWithImpl(this._self, this._then);

  final BridgeTimelineToolState_BackgroundStarted _self;
  final $Res Function(BridgeTimelineToolState_BackgroundStarted) _then;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = null,}) {
  return _then(BridgeTimelineToolState_BackgroundStarted(
startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeTimelineToolState_Interrupted extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Interrupted({required this.interruptedAt, required this.reason}): super._();


 final  PlatformInt64 interruptedAt;
 final  String reason;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineToolState_InterruptedCopyWith<BridgeTimelineToolState_Interrupted> get copyWith => _$BridgeTimelineToolState_InterruptedCopyWithImpl<BridgeTimelineToolState_Interrupted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Interrupted&&(identical(other.interruptedAt, interruptedAt) || other.interruptedAt == interruptedAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,interruptedAt,reason);
}

@override
String toString() {
    return 'BridgeTimelineToolState.interrupted(interruptedAt: $interruptedAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineToolState_InterruptedCopyWith<$Res> implements $BridgeTimelineToolStateCopyWith<$Res> {
  factory $BridgeTimelineToolState_InterruptedCopyWith(BridgeTimelineToolState_Interrupted value, $Res Function(BridgeTimelineToolState_Interrupted) _then) = _$BridgeTimelineToolState_InterruptedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 interruptedAt, String reason
});




}
/// @nodoc
class _$BridgeTimelineToolState_InterruptedCopyWithImpl<$Res>
    implements $BridgeTimelineToolState_InterruptedCopyWith<$Res> {
  _$BridgeTimelineToolState_InterruptedCopyWithImpl(this._self, this._then);

  final BridgeTimelineToolState_Interrupted _self;
  final $Res Function(BridgeTimelineToolState_Interrupted) _then;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? interruptedAt = null,Object? reason = null,}) {
  return _then(BridgeTimelineToolState_Interrupted(
interruptedAt: null == interruptedAt ? _self.interruptedAt : interruptedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeTimelineToolState_Succeeded extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Succeeded({required this.completedAt, required this.output}): super._();


 final  PlatformInt64 completedAt;
 final  BridgeTimelineToolOutputDescriptor output;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineToolState_SucceededCopyWith<BridgeTimelineToolState_Succeeded> get copyWith => _$BridgeTimelineToolState_SucceededCopyWithImpl<BridgeTimelineToolState_Succeeded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Succeeded&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.output, output) || other.output == output));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt,output);
}

@override
String toString() {
    return 'BridgeTimelineToolState.succeeded(completedAt: $completedAt, output: $output)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineToolState_SucceededCopyWith<$Res> implements $BridgeTimelineToolStateCopyWith<$Res> {
  factory $BridgeTimelineToolState_SucceededCopyWith(BridgeTimelineToolState_Succeeded value, $Res Function(BridgeTimelineToolState_Succeeded) _then) = _$BridgeTimelineToolState_SucceededCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 completedAt, BridgeTimelineToolOutputDescriptor output
});




}
/// @nodoc
class _$BridgeTimelineToolState_SucceededCopyWithImpl<$Res>
    implements $BridgeTimelineToolState_SucceededCopyWith<$Res> {
  _$BridgeTimelineToolState_SucceededCopyWithImpl(this._self, this._then);

  final BridgeTimelineToolState_Succeeded _self;
  final $Res Function(BridgeTimelineToolState_Succeeded) _then;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,Object? output = null,}) {
  return _then(BridgeTimelineToolState_Succeeded(
completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as BridgeTimelineToolOutputDescriptor,
  ));
}


}

/// @nodoc


class BridgeTimelineToolState_Failed extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Failed({required this.failedAt, required this.failure, this.output}): super._();


 final  PlatformInt64 failedAt;
 final  BridgeThreadToolFailure failure;
 final  BridgeTimelineToolOutputDescriptor? output;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineToolState_FailedCopyWith<BridgeTimelineToolState_Failed> get copyWith => _$BridgeTimelineToolState_FailedCopyWithImpl<BridgeTimelineToolState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Failed&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.failure, failure) || other.failure == failure)&&(identical(other.output, output) || other.output == output));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,failure,output);
}

@override
String toString() {
    return 'BridgeTimelineToolState.failed(failedAt: $failedAt, failure: $failure, output: $output)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineToolState_FailedCopyWith<$Res> implements $BridgeTimelineToolStateCopyWith<$Res> {
  factory $BridgeTimelineToolState_FailedCopyWith(BridgeTimelineToolState_Failed value, $Res Function(BridgeTimelineToolState_Failed) _then) = _$BridgeTimelineToolState_FailedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 failedAt, BridgeThreadToolFailure failure, BridgeTimelineToolOutputDescriptor? output
});




}
/// @nodoc
class _$BridgeTimelineToolState_FailedCopyWithImpl<$Res>
    implements $BridgeTimelineToolState_FailedCopyWith<$Res> {
  _$BridgeTimelineToolState_FailedCopyWithImpl(this._self, this._then);

  final BridgeTimelineToolState_Failed _self;
  final $Res Function(BridgeTimelineToolState_Failed) _then;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? failure = null,Object? output = freezed,}) {
  return _then(BridgeTimelineToolState_Failed(
failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeThreadToolFailure,output: freezed == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as BridgeTimelineToolOutputDescriptor?,
  ));
}


}

/// @nodoc


class BridgeTimelineToolState_Denied extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Denied({required this.deniedAt, required this.reason}): super._();


 final  PlatformInt64 deniedAt;
 final  String reason;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineToolState_DeniedCopyWith<BridgeTimelineToolState_Denied> get copyWith => _$BridgeTimelineToolState_DeniedCopyWithImpl<BridgeTimelineToolState_Denied>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Denied&&(identical(other.deniedAt, deniedAt) || other.deniedAt == deniedAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deniedAt,reason);
}

@override
String toString() {
    return 'BridgeTimelineToolState.denied(deniedAt: $deniedAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineToolState_DeniedCopyWith<$Res> implements $BridgeTimelineToolStateCopyWith<$Res> {
  factory $BridgeTimelineToolState_DeniedCopyWith(BridgeTimelineToolState_Denied value, $Res Function(BridgeTimelineToolState_Denied) _then) = _$BridgeTimelineToolState_DeniedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 deniedAt, String reason
});




}
/// @nodoc
class _$BridgeTimelineToolState_DeniedCopyWithImpl<$Res>
    implements $BridgeTimelineToolState_DeniedCopyWith<$Res> {
  _$BridgeTimelineToolState_DeniedCopyWithImpl(this._self, this._then);

  final BridgeTimelineToolState_Denied _self;
  final $Res Function(BridgeTimelineToolState_Denied) _then;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deniedAt = null,Object? reason = null,}) {
  return _then(BridgeTimelineToolState_Denied(
deniedAt: null == deniedAt ? _self.deniedAt : deniedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeTimelineToolState_Cancelled extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Cancelled({required this.cancelledAt, required this.reason}): super._();


 final  PlatformInt64 cancelledAt;
 final  String reason;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineToolState_CancelledCopyWith<BridgeTimelineToolState_Cancelled> get copyWith => _$BridgeTimelineToolState_CancelledCopyWithImpl<BridgeTimelineToolState_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Cancelled&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}

@override
String toString() {
    return 'BridgeTimelineToolState.cancelled(cancelledAt: $cancelledAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineToolState_CancelledCopyWith<$Res> implements $BridgeTimelineToolStateCopyWith<$Res> {
  factory $BridgeTimelineToolState_CancelledCopyWith(BridgeTimelineToolState_Cancelled value, $Res Function(BridgeTimelineToolState_Cancelled) _then) = _$BridgeTimelineToolState_CancelledCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 cancelledAt, String reason
});




}
/// @nodoc
class _$BridgeTimelineToolState_CancelledCopyWithImpl<$Res>
    implements $BridgeTimelineToolState_CancelledCopyWith<$Res> {
  _$BridgeTimelineToolState_CancelledCopyWithImpl(this._self, this._then);

  final BridgeTimelineToolState_Cancelled _self;
  final $Res Function(BridgeTimelineToolState_Cancelled) _then;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(BridgeTimelineToolState_Cancelled(
cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeTimelineTurnOutcome {

 PlatformInt64? get startedAt; PlatformInt64 get completedAt;
/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineTurnOutcomeCopyWith<BridgeTimelineTurnOutcome> get copyWith => _$BridgeTimelineTurnOutcomeCopyWithImpl<BridgeTimelineTurnOutcome>(this as BridgeTimelineTurnOutcome, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeTimelineTurnOutcome;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineTurnOutcome&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.completedAt, _this.completedAt) || other.completedAt == _this.completedAt));
}


@override
int get hashCode {
  final _this = this as BridgeTimelineTurnOutcome;
  return Object.hash(runtimeType,_this.startedAt,_this.completedAt);
}

@override
String toString() {
  final _this = this as BridgeTimelineTurnOutcome;
  return 'BridgeTimelineTurnOutcome(startedAt: ${_this.startedAt}, completedAt: ${_this.completedAt})';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineTurnOutcomeCopyWith<$Res>  {
  factory $BridgeTimelineTurnOutcomeCopyWith(BridgeTimelineTurnOutcome value, $Res Function(BridgeTimelineTurnOutcome) _then) = _$BridgeTimelineTurnOutcomeCopyWithImpl;
@useResult
$Res call({
 PlatformInt64? startedAt, PlatformInt64 completedAt
});




}
/// @nodoc
class _$BridgeTimelineTurnOutcomeCopyWithImpl<$Res>
    implements $BridgeTimelineTurnOutcomeCopyWith<$Res> {
  _$BridgeTimelineTurnOutcomeCopyWithImpl(this._self, this._then);

  final BridgeTimelineTurnOutcome _self;
  final $Res Function(BridgeTimelineTurnOutcome) _then;

/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? startedAt = freezed,Object? completedAt = null,}) {
  return _then(_self.copyWith(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeTimelineTurnOutcome].
extension BridgeTimelineTurnOutcomePatterns on BridgeTimelineTurnOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineTurnOutcome_Completed value)?  completed,TResult Function( BridgeTimelineTurnOutcome_Cancelled value)?  cancelled,TResult Function( BridgeTimelineTurnOutcome_Failed value)?  failed,TResult Function( BridgeTimelineTurnOutcome_BudgetLimited value)?  budgetLimited,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineTurnOutcome_Completed() when completed != null:
return completed(_that);case BridgeTimelineTurnOutcome_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeTimelineTurnOutcome_Failed() when failed != null:
return failed(_that);case BridgeTimelineTurnOutcome_BudgetLimited() when budgetLimited != null:
return budgetLimited(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineTurnOutcome_Completed value)  completed,required TResult Function( BridgeTimelineTurnOutcome_Cancelled value)  cancelled,required TResult Function( BridgeTimelineTurnOutcome_Failed value)  failed,required TResult Function( BridgeTimelineTurnOutcome_BudgetLimited value)  budgetLimited,}){
final _that = this;
switch (_that) {
case BridgeTimelineTurnOutcome_Completed():
return completed(_that);case BridgeTimelineTurnOutcome_Cancelled():
return cancelled(_that);case BridgeTimelineTurnOutcome_Failed():
return failed(_that);case BridgeTimelineTurnOutcome_BudgetLimited():
return budgetLimited(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineTurnOutcome_Completed value)?  completed,TResult? Function( BridgeTimelineTurnOutcome_Cancelled value)?  cancelled,TResult? Function( BridgeTimelineTurnOutcome_Failed value)?  failed,TResult? Function( BridgeTimelineTurnOutcome_BudgetLimited value)?  budgetLimited,}){
final _that = this;
switch (_that) {
case BridgeTimelineTurnOutcome_Completed() when completed != null:
return completed(_that);case BridgeTimelineTurnOutcome_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeTimelineTurnOutcome_Failed() when failed != null:
return failed(_that);case BridgeTimelineTurnOutcome_BudgetLimited() when budgetLimited != null:
return budgetLimited(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnCompletion completion)?  completed,TResult Function( PlatformInt64? startedAt,  PlatformInt64 requestedAt,  PlatformInt64 completedAt,  BridgeTurnCancellationCause cause)?  cancelled,TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnFailureDto failure)?  failed,TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnBudgetLimit limit,  BridgeTurnRolloverOutcome rollover)?  budgetLimited,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineTurnOutcome_Completed() when completed != null:
return completed(_that.startedAt,_that.completedAt,_that.completion);case BridgeTimelineTurnOutcome_Cancelled() when cancelled != null:
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case BridgeTimelineTurnOutcome_Failed() when failed != null:
return failed(_that.startedAt,_that.completedAt,_that.failure);case BridgeTimelineTurnOutcome_BudgetLimited() when budgetLimited != null:
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnCompletion completion)  completed,required TResult Function( PlatformInt64? startedAt,  PlatformInt64 requestedAt,  PlatformInt64 completedAt,  BridgeTurnCancellationCause cause)  cancelled,required TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnFailureDto failure)  failed,required TResult Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnBudgetLimit limit,  BridgeTurnRolloverOutcome rollover)  budgetLimited,}) {final _that = this;
switch (_that) {
case BridgeTimelineTurnOutcome_Completed():
return completed(_that.startedAt,_that.completedAt,_that.completion);case BridgeTimelineTurnOutcome_Cancelled():
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case BridgeTimelineTurnOutcome_Failed():
return failed(_that.startedAt,_that.completedAt,_that.failure);case BridgeTimelineTurnOutcome_BudgetLimited():
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnCompletion completion)?  completed,TResult? Function( PlatformInt64? startedAt,  PlatformInt64 requestedAt,  PlatformInt64 completedAt,  BridgeTurnCancellationCause cause)?  cancelled,TResult? Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnFailureDto failure)?  failed,TResult? Function( PlatformInt64? startedAt,  PlatformInt64 completedAt,  BridgeTurnBudgetLimit limit,  BridgeTurnRolloverOutcome rollover)?  budgetLimited,}) {final _that = this;
switch (_that) {
case BridgeTimelineTurnOutcome_Completed() when completed != null:
return completed(_that.startedAt,_that.completedAt,_that.completion);case BridgeTimelineTurnOutcome_Cancelled() when cancelled != null:
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case BridgeTimelineTurnOutcome_Failed() when failed != null:
return failed(_that.startedAt,_that.completedAt,_that.failure);case BridgeTimelineTurnOutcome_BudgetLimited() when budgetLimited != null:
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineTurnOutcome_Completed extends BridgeTimelineTurnOutcome {
  const BridgeTimelineTurnOutcome_Completed({this.startedAt, required this.completedAt, required this.completion}): super._();


@override final  PlatformInt64? startedAt;
@override final  PlatformInt64 completedAt;
 final  BridgeTurnCompletion completion;

/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineTurnOutcome_CompletedCopyWith<BridgeTimelineTurnOutcome_Completed> get copyWith => _$BridgeTimelineTurnOutcome_CompletedCopyWithImpl<BridgeTimelineTurnOutcome_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineTurnOutcome_Completed&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.completion, completion) || other.completion == completion));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,completion);
}

@override
String toString() {
    return 'BridgeTimelineTurnOutcome.completed(startedAt: $startedAt, completedAt: $completedAt, completion: $completion)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineTurnOutcome_CompletedCopyWith<$Res> implements $BridgeTimelineTurnOutcomeCopyWith<$Res> {
  factory $BridgeTimelineTurnOutcome_CompletedCopyWith(BridgeTimelineTurnOutcome_Completed value, $Res Function(BridgeTimelineTurnOutcome_Completed) _then) = _$BridgeTimelineTurnOutcome_CompletedCopyWithImpl;
@override @useResult
$Res call({
 PlatformInt64? startedAt, PlatformInt64 completedAt, BridgeTurnCompletion completion
});




}
/// @nodoc
class _$BridgeTimelineTurnOutcome_CompletedCopyWithImpl<$Res>
    implements $BridgeTimelineTurnOutcome_CompletedCopyWith<$Res> {
  _$BridgeTimelineTurnOutcome_CompletedCopyWithImpl(this._self, this._then);

  final BridgeTimelineTurnOutcome_Completed _self;
  final $Res Function(BridgeTimelineTurnOutcome_Completed) _then;

/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? completion = null,}) {
  return _then(BridgeTimelineTurnOutcome_Completed(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,completion: null == completion ? _self.completion : completion // ignore: cast_nullable_to_non_nullable
as BridgeTurnCompletion,
  ));
}


}

/// @nodoc


class BridgeTimelineTurnOutcome_Cancelled extends BridgeTimelineTurnOutcome {
  const BridgeTimelineTurnOutcome_Cancelled({this.startedAt, required this.requestedAt, required this.completedAt, required this.cause}): super._();


@override final  PlatformInt64? startedAt;
 final  PlatformInt64 requestedAt;
@override final  PlatformInt64 completedAt;
 final  BridgeTurnCancellationCause cause;

/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineTurnOutcome_CancelledCopyWith<BridgeTimelineTurnOutcome_Cancelled> get copyWith => _$BridgeTimelineTurnOutcome_CancelledCopyWithImpl<BridgeTimelineTurnOutcome_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineTurnOutcome_Cancelled&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.requestedAt, requestedAt) || other.requestedAt == requestedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.cause, cause) || other.cause == cause));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,requestedAt,completedAt,cause);
}

@override
String toString() {
    return 'BridgeTimelineTurnOutcome.cancelled(startedAt: $startedAt, requestedAt: $requestedAt, completedAt: $completedAt, cause: $cause)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineTurnOutcome_CancelledCopyWith<$Res> implements $BridgeTimelineTurnOutcomeCopyWith<$Res> {
  factory $BridgeTimelineTurnOutcome_CancelledCopyWith(BridgeTimelineTurnOutcome_Cancelled value, $Res Function(BridgeTimelineTurnOutcome_Cancelled) _then) = _$BridgeTimelineTurnOutcome_CancelledCopyWithImpl;
@override @useResult
$Res call({
 PlatformInt64? startedAt, PlatformInt64 requestedAt, PlatformInt64 completedAt, BridgeTurnCancellationCause cause
});


$BridgeTurnCancellationCauseCopyWith<$Res> get cause;

}
/// @nodoc
class _$BridgeTimelineTurnOutcome_CancelledCopyWithImpl<$Res>
    implements $BridgeTimelineTurnOutcome_CancelledCopyWith<$Res> {
  _$BridgeTimelineTurnOutcome_CancelledCopyWithImpl(this._self, this._then);

  final BridgeTimelineTurnOutcome_Cancelled _self;
  final $Res Function(BridgeTimelineTurnOutcome_Cancelled) _then;

/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? requestedAt = null,Object? completedAt = null,Object? cause = null,}) {
  return _then(BridgeTimelineTurnOutcome_Cancelled(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,requestedAt: null == requestedAt ? _self.requestedAt : requestedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,cause: null == cause ? _self.cause : cause // ignore: cast_nullable_to_non_nullable
as BridgeTurnCancellationCause,
  ));
}

/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeTurnCancellationCauseCopyWith<$Res> get cause {

  return $BridgeTurnCancellationCauseCopyWith<$Res>(_self.cause, (value) {
    return _then(_self.copyWith(cause: value));
  });
}
}

/// @nodoc


class BridgeTimelineTurnOutcome_Failed extends BridgeTimelineTurnOutcome {
  const BridgeTimelineTurnOutcome_Failed({this.startedAt, required this.completedAt, required this.failure}): super._();


@override final  PlatformInt64? startedAt;
@override final  PlatformInt64 completedAt;
 final  BridgeTurnFailureDto failure;

/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineTurnOutcome_FailedCopyWith<BridgeTimelineTurnOutcome_Failed> get copyWith => _$BridgeTimelineTurnOutcome_FailedCopyWithImpl<BridgeTimelineTurnOutcome_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineTurnOutcome_Failed&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,failure);
}

@override
String toString() {
    return 'BridgeTimelineTurnOutcome.failed(startedAt: $startedAt, completedAt: $completedAt, failure: $failure)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineTurnOutcome_FailedCopyWith<$Res> implements $BridgeTimelineTurnOutcomeCopyWith<$Res> {
  factory $BridgeTimelineTurnOutcome_FailedCopyWith(BridgeTimelineTurnOutcome_Failed value, $Res Function(BridgeTimelineTurnOutcome_Failed) _then) = _$BridgeTimelineTurnOutcome_FailedCopyWithImpl;
@override @useResult
$Res call({
 PlatformInt64? startedAt, PlatformInt64 completedAt, BridgeTurnFailureDto failure
});




}
/// @nodoc
class _$BridgeTimelineTurnOutcome_FailedCopyWithImpl<$Res>
    implements $BridgeTimelineTurnOutcome_FailedCopyWith<$Res> {
  _$BridgeTimelineTurnOutcome_FailedCopyWithImpl(this._self, this._then);

  final BridgeTimelineTurnOutcome_Failed _self;
  final $Res Function(BridgeTimelineTurnOutcome_Failed) _then;

/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? failure = null,}) {
  return _then(BridgeTimelineTurnOutcome_Failed(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeTurnFailureDto,
  ));
}


}

/// @nodoc


class BridgeTimelineTurnOutcome_BudgetLimited extends BridgeTimelineTurnOutcome {
  const BridgeTimelineTurnOutcome_BudgetLimited({this.startedAt, required this.completedAt, required this.limit, required this.rollover}): super._();


@override final  PlatformInt64? startedAt;
@override final  PlatformInt64 completedAt;
 final  BridgeTurnBudgetLimit limit;
 final  BridgeTurnRolloverOutcome rollover;

/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineTurnOutcome_BudgetLimitedCopyWith<BridgeTimelineTurnOutcome_BudgetLimited> get copyWith => _$BridgeTimelineTurnOutcome_BudgetLimitedCopyWithImpl<BridgeTimelineTurnOutcome_BudgetLimited>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineTurnOutcome_BudgetLimited&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.limit, limit) || other.limit == limit)&&(identical(other.rollover, rollover) || other.rollover == rollover));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,limit,rollover);
}

@override
String toString() {
    return 'BridgeTimelineTurnOutcome.budgetLimited(startedAt: $startedAt, completedAt: $completedAt, limit: $limit, rollover: $rollover)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineTurnOutcome_BudgetLimitedCopyWith<$Res> implements $BridgeTimelineTurnOutcomeCopyWith<$Res> {
  factory $BridgeTimelineTurnOutcome_BudgetLimitedCopyWith(BridgeTimelineTurnOutcome_BudgetLimited value, $Res Function(BridgeTimelineTurnOutcome_BudgetLimited) _then) = _$BridgeTimelineTurnOutcome_BudgetLimitedCopyWithImpl;
@override @useResult
$Res call({
 PlatformInt64? startedAt, PlatformInt64 completedAt, BridgeTurnBudgetLimit limit, BridgeTurnRolloverOutcome rollover
});


$BridgeTurnRolloverOutcomeCopyWith<$Res> get rollover;

}
/// @nodoc
class _$BridgeTimelineTurnOutcome_BudgetLimitedCopyWithImpl<$Res>
    implements $BridgeTimelineTurnOutcome_BudgetLimitedCopyWith<$Res> {
  _$BridgeTimelineTurnOutcome_BudgetLimitedCopyWithImpl(this._self, this._then);

  final BridgeTimelineTurnOutcome_BudgetLimited _self;
  final $Res Function(BridgeTimelineTurnOutcome_BudgetLimited) _then;

/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? limit = null,Object? rollover = null,}) {
  return _then(BridgeTimelineTurnOutcome_BudgetLimited(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as BridgeTurnBudgetLimit,rollover: null == rollover ? _self.rollover : rollover // ignore: cast_nullable_to_non_nullable
as BridgeTurnRolloverOutcome,
  ));
}

/// Create a copy of BridgeTimelineTurnOutcome
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeTurnRolloverOutcomeCopyWith<$Res> get rollover {

  return $BridgeTurnRolloverOutcomeCopyWith<$Res>(_self.rollover, (value) {
    return _then(_self.copyWith(rollover: value));
  });
}
}

/// @nodoc
mixin _$BridgeTimelineUserInputState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineUserInputState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineUserInputState()';
}


}

/// @nodoc
class $BridgeTimelineUserInputStateCopyWith<$Res>  {
$BridgeTimelineUserInputStateCopyWith(BridgeTimelineUserInputState _, $Res Function(BridgeTimelineUserInputState) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelineUserInputState].
extension BridgeTimelineUserInputStatePatterns on BridgeTimelineUserInputState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineUserInputState_Cancelled value)?  cancelled,TResult Function( BridgeTimelineUserInputState_Resolved value)?  resolved,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeTimelineUserInputState_Resolved() when resolved != null:
return resolved(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineUserInputState_Cancelled value)  cancelled,required TResult Function( BridgeTimelineUserInputState_Resolved value)  resolved,}){
final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Cancelled():
return cancelled(_that);case BridgeTimelineUserInputState_Resolved():
return resolved(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineUserInputState_Cancelled value)?  cancelled,TResult? Function( BridgeTimelineUserInputState_Resolved value)?  resolved,}){
final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeTimelineUserInputState_Resolved() when resolved != null:
return resolved(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  cancelled,TResult Function( List<BridgeTimelineAnswerDescriptor> answers)?  resolved,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Cancelled() when cancelled != null:
return cancelled();case BridgeTimelineUserInputState_Resolved() when resolved != null:
return resolved(_that.answers);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  cancelled,required TResult Function( List<BridgeTimelineAnswerDescriptor> answers)  resolved,}) {final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Cancelled():
return cancelled();case BridgeTimelineUserInputState_Resolved():
return resolved(_that.answers);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  cancelled,TResult? Function( List<BridgeTimelineAnswerDescriptor> answers)?  resolved,}) {final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Cancelled() when cancelled != null:
return cancelled();case BridgeTimelineUserInputState_Resolved() when resolved != null:
return resolved(_that.answers);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineUserInputState_Cancelled extends BridgeTimelineUserInputState {
  const BridgeTimelineUserInputState_Cancelled(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineUserInputState_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineUserInputState.cancelled()';
}


}




/// @nodoc


class BridgeTimelineUserInputState_Resolved extends BridgeTimelineUserInputState {
  const BridgeTimelineUserInputState_Resolved({required  List<BridgeTimelineAnswerDescriptor> answers}): _answers = answers,super._();


 final  List<BridgeTimelineAnswerDescriptor> _answers;
 List<BridgeTimelineAnswerDescriptor> get answers {
  if (_answers is EqualUnmodifiableListView) return _answers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_answers);
}


/// Create a copy of BridgeTimelineUserInputState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineUserInputState_ResolvedCopyWith<BridgeTimelineUserInputState_Resolved> get copyWith => _$BridgeTimelineUserInputState_ResolvedCopyWithImpl<BridgeTimelineUserInputState_Resolved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineUserInputState_Resolved&&const DeepCollectionEquality().equals(other.answers, _answers));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_answers));
}

@override
String toString() {
    return 'BridgeTimelineUserInputState.resolved(answers: $answers)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineUserInputState_ResolvedCopyWith<$Res> implements $BridgeTimelineUserInputStateCopyWith<$Res> {
  factory $BridgeTimelineUserInputState_ResolvedCopyWith(BridgeTimelineUserInputState_Resolved value, $Res Function(BridgeTimelineUserInputState_Resolved) _then) = _$BridgeTimelineUserInputState_ResolvedCopyWithImpl;
@useResult
$Res call({
 List<BridgeTimelineAnswerDescriptor> answers
});




}
/// @nodoc
class _$BridgeTimelineUserInputState_ResolvedCopyWithImpl<$Res>
    implements $BridgeTimelineUserInputState_ResolvedCopyWith<$Res> {
  _$BridgeTimelineUserInputState_ResolvedCopyWithImpl(this._self, this._then);

  final BridgeTimelineUserInputState_Resolved _self;
  final $Res Function(BridgeTimelineUserInputState_Resolved) _then;

/// Create a copy of BridgeTimelineUserInputState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? answers = null,}) {
  return _then(BridgeTimelineUserInputState_Resolved(
answers: null == answers ? _self._answers : answers // ignore: cast_nullable_to_non_nullable
as List<BridgeTimelineAnswerDescriptor>,
  ));
}


}

// dart format on
