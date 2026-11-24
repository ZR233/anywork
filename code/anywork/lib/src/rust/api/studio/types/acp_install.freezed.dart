// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_install.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAcpInstallAvailability {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallAvailability);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpInstallAvailability()';
}


}

/// @nodoc
class $BridgeAcpInstallAvailabilityCopyWith<$Res>  {
$BridgeAcpInstallAvailabilityCopyWith(BridgeAcpInstallAvailability _, $Res Function(BridgeAcpInstallAvailability) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpInstallAvailability].
extension BridgeAcpInstallAvailabilityPatterns on BridgeAcpInstallAvailability {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpInstallAvailability_Available value)?  available,TResult Function( BridgeAcpInstallAvailability_UnsupportedPlatform value)?  unsupportedPlatform,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpInstallAvailability_Available() when available != null:
return available(_that);case BridgeAcpInstallAvailability_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpInstallAvailability_Available value)  available,required TResult Function( BridgeAcpInstallAvailability_UnsupportedPlatform value)  unsupportedPlatform,}){
final _that = this;
switch (_that) {
case BridgeAcpInstallAvailability_Available():
return available(_that);case BridgeAcpInstallAvailability_UnsupportedPlatform():
return unsupportedPlatform(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpInstallAvailability_Available value)?  available,TResult? Function( BridgeAcpInstallAvailability_UnsupportedPlatform value)?  unsupportedPlatform,}){
final _that = this;
switch (_that) {
case BridgeAcpInstallAvailability_Available() when available != null:
return available(_that);case BridgeAcpInstallAvailability_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String target)?  available,TResult Function()?  unsupportedPlatform,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpInstallAvailability_Available() when available != null:
return available(_that.target);case BridgeAcpInstallAvailability_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String target)  available,required TResult Function()  unsupportedPlatform,}) {final _that = this;
switch (_that) {
case BridgeAcpInstallAvailability_Available():
return available(_that.target);case BridgeAcpInstallAvailability_UnsupportedPlatform():
return unsupportedPlatform();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String target)?  available,TResult? Function()?  unsupportedPlatform,}) {final _that = this;
switch (_that) {
case BridgeAcpInstallAvailability_Available() when available != null:
return available(_that.target);case BridgeAcpInstallAvailability_UnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform();case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpInstallAvailability_Available extends BridgeAcpInstallAvailability {
  const BridgeAcpInstallAvailability_Available({required this.target}): super._();


 final  String target;

/// Create a copy of BridgeAcpInstallAvailability
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallAvailability_AvailableCopyWith<BridgeAcpInstallAvailability_Available> get copyWith => _$BridgeAcpInstallAvailability_AvailableCopyWithImpl<BridgeAcpInstallAvailability_Available>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallAvailability_Available&&(identical(other.target, target) || other.target == target));
}


@override
int get hashCode {
    return Object.hash(runtimeType,target);
}

@override
String toString() {
    return 'BridgeAcpInstallAvailability.available(target: $target)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallAvailability_AvailableCopyWith<$Res> implements $BridgeAcpInstallAvailabilityCopyWith<$Res> {
  factory $BridgeAcpInstallAvailability_AvailableCopyWith(BridgeAcpInstallAvailability_Available value, $Res Function(BridgeAcpInstallAvailability_Available) _then) = _$BridgeAcpInstallAvailability_AvailableCopyWithImpl;
@useResult
$Res call({
 String target
});




}
/// @nodoc
class _$BridgeAcpInstallAvailability_AvailableCopyWithImpl<$Res>
    implements $BridgeAcpInstallAvailability_AvailableCopyWith<$Res> {
  _$BridgeAcpInstallAvailability_AvailableCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallAvailability_Available _self;
  final $Res Function(BridgeAcpInstallAvailability_Available) _then;

/// Create a copy of BridgeAcpInstallAvailability
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? target = null,}) {
  return _then(BridgeAcpInstallAvailability_Available(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpInstallAvailability_UnsupportedPlatform extends BridgeAcpInstallAvailability {
  const BridgeAcpInstallAvailability_UnsupportedPlatform(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallAvailability_UnsupportedPlatform);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpInstallAvailability.unsupportedPlatform()';
}


}




/// @nodoc
mixin _$BridgeAcpInstallState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpInstallState()';
}


}

/// @nodoc
class $BridgeAcpInstallStateCopyWith<$Res>  {
$BridgeAcpInstallStateCopyWith(BridgeAcpInstallState _, $Res Function(BridgeAcpInstallState) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpInstallState].
extension BridgeAcpInstallStatePatterns on BridgeAcpInstallState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpInstallState_Idle value)?  idle,TResult Function( BridgeAcpInstallState_Resolving value)?  resolving,TResult Function( BridgeAcpInstallState_Waiting value)?  waiting,TResult Function( BridgeAcpInstallState_Downloading value)?  downloading,TResult Function( BridgeAcpInstallState_Verifying value)?  verifying,TResult Function( BridgeAcpInstallState_Extracting value)?  extracting,TResult Function( BridgeAcpInstallState_Publishing value)?  publishing,TResult Function( BridgeAcpInstallState_Closing value)?  closing,TResult Function( BridgeAcpInstallState_Ready value)?  ready,TResult Function( BridgeAcpInstallState_Cancelling value)?  cancelling,TResult Function( BridgeAcpInstallState_Cancelled value)?  cancelled,TResult Function( BridgeAcpInstallState_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpInstallState_Idle() when idle != null:
return idle(_that);case BridgeAcpInstallState_Resolving() when resolving != null:
return resolving(_that);case BridgeAcpInstallState_Waiting() when waiting != null:
return waiting(_that);case BridgeAcpInstallState_Downloading() when downloading != null:
return downloading(_that);case BridgeAcpInstallState_Verifying() when verifying != null:
return verifying(_that);case BridgeAcpInstallState_Extracting() when extracting != null:
return extracting(_that);case BridgeAcpInstallState_Publishing() when publishing != null:
return publishing(_that);case BridgeAcpInstallState_Closing() when closing != null:
return closing(_that);case BridgeAcpInstallState_Ready() when ready != null:
return ready(_that);case BridgeAcpInstallState_Cancelling() when cancelling != null:
return cancelling(_that);case BridgeAcpInstallState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeAcpInstallState_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpInstallState_Idle value)  idle,required TResult Function( BridgeAcpInstallState_Resolving value)  resolving,required TResult Function( BridgeAcpInstallState_Waiting value)  waiting,required TResult Function( BridgeAcpInstallState_Downloading value)  downloading,required TResult Function( BridgeAcpInstallState_Verifying value)  verifying,required TResult Function( BridgeAcpInstallState_Extracting value)  extracting,required TResult Function( BridgeAcpInstallState_Publishing value)  publishing,required TResult Function( BridgeAcpInstallState_Closing value)  closing,required TResult Function( BridgeAcpInstallState_Ready value)  ready,required TResult Function( BridgeAcpInstallState_Cancelling value)  cancelling,required TResult Function( BridgeAcpInstallState_Cancelled value)  cancelled,required TResult Function( BridgeAcpInstallState_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeAcpInstallState_Idle():
return idle(_that);case BridgeAcpInstallState_Resolving():
return resolving(_that);case BridgeAcpInstallState_Waiting():
return waiting(_that);case BridgeAcpInstallState_Downloading():
return downloading(_that);case BridgeAcpInstallState_Verifying():
return verifying(_that);case BridgeAcpInstallState_Extracting():
return extracting(_that);case BridgeAcpInstallState_Publishing():
return publishing(_that);case BridgeAcpInstallState_Closing():
return closing(_that);case BridgeAcpInstallState_Ready():
return ready(_that);case BridgeAcpInstallState_Cancelling():
return cancelling(_that);case BridgeAcpInstallState_Cancelled():
return cancelled(_that);case BridgeAcpInstallState_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpInstallState_Idle value)?  idle,TResult? Function( BridgeAcpInstallState_Resolving value)?  resolving,TResult? Function( BridgeAcpInstallState_Waiting value)?  waiting,TResult? Function( BridgeAcpInstallState_Downloading value)?  downloading,TResult? Function( BridgeAcpInstallState_Verifying value)?  verifying,TResult? Function( BridgeAcpInstallState_Extracting value)?  extracting,TResult? Function( BridgeAcpInstallState_Publishing value)?  publishing,TResult? Function( BridgeAcpInstallState_Closing value)?  closing,TResult? Function( BridgeAcpInstallState_Ready value)?  ready,TResult? Function( BridgeAcpInstallState_Cancelling value)?  cancelling,TResult? Function( BridgeAcpInstallState_Cancelled value)?  cancelled,TResult? Function( BridgeAcpInstallState_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeAcpInstallState_Idle() when idle != null:
return idle(_that);case BridgeAcpInstallState_Resolving() when resolving != null:
return resolving(_that);case BridgeAcpInstallState_Waiting() when waiting != null:
return waiting(_that);case BridgeAcpInstallState_Downloading() when downloading != null:
return downloading(_that);case BridgeAcpInstallState_Verifying() when verifying != null:
return verifying(_that);case BridgeAcpInstallState_Extracting() when extracting != null:
return extracting(_that);case BridgeAcpInstallState_Publishing() when publishing != null:
return publishing(_that);case BridgeAcpInstallState_Closing() when closing != null:
return closing(_that);case BridgeAcpInstallState_Ready() when ready != null:
return ready(_that);case BridgeAcpInstallState_Cancelling() when cancelling != null:
return cancelling(_that);case BridgeAcpInstallState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeAcpInstallState_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( String operationId)?  resolving,TResult Function( String operationId,  BridgeAcpInstallRelease release)?  waiting,TResult Function( String operationId,  BridgeAcpInstallRelease release,  BridgeAcpInstallProgress progress,  int retryCount)?  downloading,TResult Function( String operationId,  BridgeAcpInstallRelease release,  BridgeAcpInstallProgress progress)?  verifying,TResult Function( String operationId,  BridgeAcpInstallRelease release,  BridgeAcpInstallProgress progress)?  extracting,TResult Function( String operationId,  BridgeAcpInstallRelease release)?  publishing,TResult Function( String operationId,  BridgeAcpInstallFailure? failure)?  closing,TResult Function( String operationId,  BridgeAcpInstalledServer server)?  ready,TResult Function( String operationId)?  cancelling,TResult Function( String operationId)?  cancelled,TResult Function( String operationId,  BridgeAcpInstallFailure failure)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpInstallState_Idle() when idle != null:
return idle();case BridgeAcpInstallState_Resolving() when resolving != null:
return resolving(_that.operationId);case BridgeAcpInstallState_Waiting() when waiting != null:
return waiting(_that.operationId,_that.release);case BridgeAcpInstallState_Downloading() when downloading != null:
return downloading(_that.operationId,_that.release,_that.progress,_that.retryCount);case BridgeAcpInstallState_Verifying() when verifying != null:
return verifying(_that.operationId,_that.release,_that.progress);case BridgeAcpInstallState_Extracting() when extracting != null:
return extracting(_that.operationId,_that.release,_that.progress);case BridgeAcpInstallState_Publishing() when publishing != null:
return publishing(_that.operationId,_that.release);case BridgeAcpInstallState_Closing() when closing != null:
return closing(_that.operationId,_that.failure);case BridgeAcpInstallState_Ready() when ready != null:
return ready(_that.operationId,_that.server);case BridgeAcpInstallState_Cancelling() when cancelling != null:
return cancelling(_that.operationId);case BridgeAcpInstallState_Cancelled() when cancelled != null:
return cancelled(_that.operationId);case BridgeAcpInstallState_Failed() when failed != null:
return failed(_that.operationId,_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( String operationId)  resolving,required TResult Function( String operationId,  BridgeAcpInstallRelease release)  waiting,required TResult Function( String operationId,  BridgeAcpInstallRelease release,  BridgeAcpInstallProgress progress,  int retryCount)  downloading,required TResult Function( String operationId,  BridgeAcpInstallRelease release,  BridgeAcpInstallProgress progress)  verifying,required TResult Function( String operationId,  BridgeAcpInstallRelease release,  BridgeAcpInstallProgress progress)  extracting,required TResult Function( String operationId,  BridgeAcpInstallRelease release)  publishing,required TResult Function( String operationId,  BridgeAcpInstallFailure? failure)  closing,required TResult Function( String operationId,  BridgeAcpInstalledServer server)  ready,required TResult Function( String operationId)  cancelling,required TResult Function( String operationId)  cancelled,required TResult Function( String operationId,  BridgeAcpInstallFailure failure)  failed,}) {final _that = this;
switch (_that) {
case BridgeAcpInstallState_Idle():
return idle();case BridgeAcpInstallState_Resolving():
return resolving(_that.operationId);case BridgeAcpInstallState_Waiting():
return waiting(_that.operationId,_that.release);case BridgeAcpInstallState_Downloading():
return downloading(_that.operationId,_that.release,_that.progress,_that.retryCount);case BridgeAcpInstallState_Verifying():
return verifying(_that.operationId,_that.release,_that.progress);case BridgeAcpInstallState_Extracting():
return extracting(_that.operationId,_that.release,_that.progress);case BridgeAcpInstallState_Publishing():
return publishing(_that.operationId,_that.release);case BridgeAcpInstallState_Closing():
return closing(_that.operationId,_that.failure);case BridgeAcpInstallState_Ready():
return ready(_that.operationId,_that.server);case BridgeAcpInstallState_Cancelling():
return cancelling(_that.operationId);case BridgeAcpInstallState_Cancelled():
return cancelled(_that.operationId);case BridgeAcpInstallState_Failed():
return failed(_that.operationId,_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( String operationId)?  resolving,TResult? Function( String operationId,  BridgeAcpInstallRelease release)?  waiting,TResult? Function( String operationId,  BridgeAcpInstallRelease release,  BridgeAcpInstallProgress progress,  int retryCount)?  downloading,TResult? Function( String operationId,  BridgeAcpInstallRelease release,  BridgeAcpInstallProgress progress)?  verifying,TResult? Function( String operationId,  BridgeAcpInstallRelease release,  BridgeAcpInstallProgress progress)?  extracting,TResult? Function( String operationId,  BridgeAcpInstallRelease release)?  publishing,TResult? Function( String operationId,  BridgeAcpInstallFailure? failure)?  closing,TResult? Function( String operationId,  BridgeAcpInstalledServer server)?  ready,TResult? Function( String operationId)?  cancelling,TResult? Function( String operationId)?  cancelled,TResult? Function( String operationId,  BridgeAcpInstallFailure failure)?  failed,}) {final _that = this;
switch (_that) {
case BridgeAcpInstallState_Idle() when idle != null:
return idle();case BridgeAcpInstallState_Resolving() when resolving != null:
return resolving(_that.operationId);case BridgeAcpInstallState_Waiting() when waiting != null:
return waiting(_that.operationId,_that.release);case BridgeAcpInstallState_Downloading() when downloading != null:
return downloading(_that.operationId,_that.release,_that.progress,_that.retryCount);case BridgeAcpInstallState_Verifying() when verifying != null:
return verifying(_that.operationId,_that.release,_that.progress);case BridgeAcpInstallState_Extracting() when extracting != null:
return extracting(_that.operationId,_that.release,_that.progress);case BridgeAcpInstallState_Publishing() when publishing != null:
return publishing(_that.operationId,_that.release);case BridgeAcpInstallState_Closing() when closing != null:
return closing(_that.operationId,_that.failure);case BridgeAcpInstallState_Ready() when ready != null:
return ready(_that.operationId,_that.server);case BridgeAcpInstallState_Cancelling() when cancelling != null:
return cancelling(_that.operationId);case BridgeAcpInstallState_Cancelled() when cancelled != null:
return cancelled(_that.operationId);case BridgeAcpInstallState_Failed() when failed != null:
return failed(_that.operationId,_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpInstallState_Idle extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Idle(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpInstallState.idle()';
}


}




/// @nodoc


class BridgeAcpInstallState_Resolving extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Resolving({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallState_ResolvingCopyWith<BridgeAcpInstallState_Resolving> get copyWith => _$BridgeAcpInstallState_ResolvingCopyWithImpl<BridgeAcpInstallState_Resolving>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Resolving&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}

@override
String toString() {
    return 'BridgeAcpInstallState.resolving(operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallState_ResolvingCopyWith<$Res> implements $BridgeAcpInstallStateCopyWith<$Res> {
  factory $BridgeAcpInstallState_ResolvingCopyWith(BridgeAcpInstallState_Resolving value, $Res Function(BridgeAcpInstallState_Resolving) _then) = _$BridgeAcpInstallState_ResolvingCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BridgeAcpInstallState_ResolvingCopyWithImpl<$Res>
    implements $BridgeAcpInstallState_ResolvingCopyWith<$Res> {
  _$BridgeAcpInstallState_ResolvingCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallState_Resolving _self;
  final $Res Function(BridgeAcpInstallState_Resolving) _then;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BridgeAcpInstallState_Resolving(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpInstallState_Waiting extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Waiting({required this.operationId, required this.release}): super._();


 final  String operationId;
 final  BridgeAcpInstallRelease release;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallState_WaitingCopyWith<BridgeAcpInstallState_Waiting> get copyWith => _$BridgeAcpInstallState_WaitingCopyWithImpl<BridgeAcpInstallState_Waiting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Waiting&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.release, release) || other.release == release));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,release);
}

@override
String toString() {
    return 'BridgeAcpInstallState.waiting(operationId: $operationId, release: $release)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallState_WaitingCopyWith<$Res> implements $BridgeAcpInstallStateCopyWith<$Res> {
  factory $BridgeAcpInstallState_WaitingCopyWith(BridgeAcpInstallState_Waiting value, $Res Function(BridgeAcpInstallState_Waiting) _then) = _$BridgeAcpInstallState_WaitingCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeAcpInstallRelease release
});




}
/// @nodoc
class _$BridgeAcpInstallState_WaitingCopyWithImpl<$Res>
    implements $BridgeAcpInstallState_WaitingCopyWith<$Res> {
  _$BridgeAcpInstallState_WaitingCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallState_Waiting _self;
  final $Res Function(BridgeAcpInstallState_Waiting) _then;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? release = null,}) {
  return _then(BridgeAcpInstallState_Waiting(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,release: null == release ? _self.release : release // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallRelease,
  ));
}


}

/// @nodoc


class BridgeAcpInstallState_Downloading extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Downloading({required this.operationId, required this.release, required this.progress, required this.retryCount}): super._();


 final  String operationId;
 final  BridgeAcpInstallRelease release;
 final  BridgeAcpInstallProgress progress;
 final  int retryCount;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallState_DownloadingCopyWith<BridgeAcpInstallState_Downloading> get copyWith => _$BridgeAcpInstallState_DownloadingCopyWithImpl<BridgeAcpInstallState_Downloading>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Downloading&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.release, release) || other.release == release)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.retryCount, retryCount) || other.retryCount == retryCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,release,progress,retryCount);
}

@override
String toString() {
    return 'BridgeAcpInstallState.downloading(operationId: $operationId, release: $release, progress: $progress, retryCount: $retryCount)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallState_DownloadingCopyWith<$Res> implements $BridgeAcpInstallStateCopyWith<$Res> {
  factory $BridgeAcpInstallState_DownloadingCopyWith(BridgeAcpInstallState_Downloading value, $Res Function(BridgeAcpInstallState_Downloading) _then) = _$BridgeAcpInstallState_DownloadingCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeAcpInstallRelease release, BridgeAcpInstallProgress progress, int retryCount
});




}
/// @nodoc
class _$BridgeAcpInstallState_DownloadingCopyWithImpl<$Res>
    implements $BridgeAcpInstallState_DownloadingCopyWith<$Res> {
  _$BridgeAcpInstallState_DownloadingCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallState_Downloading _self;
  final $Res Function(BridgeAcpInstallState_Downloading) _then;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? release = null,Object? progress = null,Object? retryCount = null,}) {
  return _then(BridgeAcpInstallState_Downloading(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,release: null == release ? _self.release : release // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallRelease,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallProgress,retryCount: null == retryCount ? _self.retryCount : retryCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BridgeAcpInstallState_Verifying extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Verifying({required this.operationId, required this.release, required this.progress}): super._();


 final  String operationId;
 final  BridgeAcpInstallRelease release;
 final  BridgeAcpInstallProgress progress;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallState_VerifyingCopyWith<BridgeAcpInstallState_Verifying> get copyWith => _$BridgeAcpInstallState_VerifyingCopyWithImpl<BridgeAcpInstallState_Verifying>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Verifying&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.release, release) || other.release == release)&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,release,progress);
}

@override
String toString() {
    return 'BridgeAcpInstallState.verifying(operationId: $operationId, release: $release, progress: $progress)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallState_VerifyingCopyWith<$Res> implements $BridgeAcpInstallStateCopyWith<$Res> {
  factory $BridgeAcpInstallState_VerifyingCopyWith(BridgeAcpInstallState_Verifying value, $Res Function(BridgeAcpInstallState_Verifying) _then) = _$BridgeAcpInstallState_VerifyingCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeAcpInstallRelease release, BridgeAcpInstallProgress progress
});




}
/// @nodoc
class _$BridgeAcpInstallState_VerifyingCopyWithImpl<$Res>
    implements $BridgeAcpInstallState_VerifyingCopyWith<$Res> {
  _$BridgeAcpInstallState_VerifyingCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallState_Verifying _self;
  final $Res Function(BridgeAcpInstallState_Verifying) _then;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? release = null,Object? progress = null,}) {
  return _then(BridgeAcpInstallState_Verifying(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,release: null == release ? _self.release : release // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallRelease,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallProgress,
  ));
}


}

/// @nodoc


class BridgeAcpInstallState_Extracting extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Extracting({required this.operationId, required this.release, required this.progress}): super._();


 final  String operationId;
 final  BridgeAcpInstallRelease release;
 final  BridgeAcpInstallProgress progress;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallState_ExtractingCopyWith<BridgeAcpInstallState_Extracting> get copyWith => _$BridgeAcpInstallState_ExtractingCopyWithImpl<BridgeAcpInstallState_Extracting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Extracting&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.release, release) || other.release == release)&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,release,progress);
}

@override
String toString() {
    return 'BridgeAcpInstallState.extracting(operationId: $operationId, release: $release, progress: $progress)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallState_ExtractingCopyWith<$Res> implements $BridgeAcpInstallStateCopyWith<$Res> {
  factory $BridgeAcpInstallState_ExtractingCopyWith(BridgeAcpInstallState_Extracting value, $Res Function(BridgeAcpInstallState_Extracting) _then) = _$BridgeAcpInstallState_ExtractingCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeAcpInstallRelease release, BridgeAcpInstallProgress progress
});




}
/// @nodoc
class _$BridgeAcpInstallState_ExtractingCopyWithImpl<$Res>
    implements $BridgeAcpInstallState_ExtractingCopyWith<$Res> {
  _$BridgeAcpInstallState_ExtractingCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallState_Extracting _self;
  final $Res Function(BridgeAcpInstallState_Extracting) _then;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? release = null,Object? progress = null,}) {
  return _then(BridgeAcpInstallState_Extracting(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,release: null == release ? _self.release : release // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallRelease,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallProgress,
  ));
}


}

/// @nodoc


class BridgeAcpInstallState_Publishing extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Publishing({required this.operationId, required this.release}): super._();


 final  String operationId;
 final  BridgeAcpInstallRelease release;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallState_PublishingCopyWith<BridgeAcpInstallState_Publishing> get copyWith => _$BridgeAcpInstallState_PublishingCopyWithImpl<BridgeAcpInstallState_Publishing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Publishing&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.release, release) || other.release == release));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,release);
}

@override
String toString() {
    return 'BridgeAcpInstallState.publishing(operationId: $operationId, release: $release)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallState_PublishingCopyWith<$Res> implements $BridgeAcpInstallStateCopyWith<$Res> {
  factory $BridgeAcpInstallState_PublishingCopyWith(BridgeAcpInstallState_Publishing value, $Res Function(BridgeAcpInstallState_Publishing) _then) = _$BridgeAcpInstallState_PublishingCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeAcpInstallRelease release
});




}
/// @nodoc
class _$BridgeAcpInstallState_PublishingCopyWithImpl<$Res>
    implements $BridgeAcpInstallState_PublishingCopyWith<$Res> {
  _$BridgeAcpInstallState_PublishingCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallState_Publishing _self;
  final $Res Function(BridgeAcpInstallState_Publishing) _then;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? release = null,}) {
  return _then(BridgeAcpInstallState_Publishing(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,release: null == release ? _self.release : release // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallRelease,
  ));
}


}

/// @nodoc


class BridgeAcpInstallState_Closing extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Closing({required this.operationId, this.failure}): super._();


 final  String operationId;
 final  BridgeAcpInstallFailure? failure;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallState_ClosingCopyWith<BridgeAcpInstallState_Closing> get copyWith => _$BridgeAcpInstallState_ClosingCopyWithImpl<BridgeAcpInstallState_Closing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Closing&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,failure);
}

@override
String toString() {
    return 'BridgeAcpInstallState.closing(operationId: $operationId, failure: $failure)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallState_ClosingCopyWith<$Res> implements $BridgeAcpInstallStateCopyWith<$Res> {
  factory $BridgeAcpInstallState_ClosingCopyWith(BridgeAcpInstallState_Closing value, $Res Function(BridgeAcpInstallState_Closing) _then) = _$BridgeAcpInstallState_ClosingCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeAcpInstallFailure? failure
});




}
/// @nodoc
class _$BridgeAcpInstallState_ClosingCopyWithImpl<$Res>
    implements $BridgeAcpInstallState_ClosingCopyWith<$Res> {
  _$BridgeAcpInstallState_ClosingCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallState_Closing _self;
  final $Res Function(BridgeAcpInstallState_Closing) _then;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? failure = freezed,}) {
  return _then(BridgeAcpInstallState_Closing(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallFailure?,
  ));
}


}

/// @nodoc


class BridgeAcpInstallState_Ready extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Ready({required this.operationId, required this.server}): super._();


 final  String operationId;
 final  BridgeAcpInstalledServer server;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallState_ReadyCopyWith<BridgeAcpInstallState_Ready> get copyWith => _$BridgeAcpInstallState_ReadyCopyWithImpl<BridgeAcpInstallState_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Ready&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.server, server) || other.server == server));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,server);
}

@override
String toString() {
    return 'BridgeAcpInstallState.ready(operationId: $operationId, server: $server)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallState_ReadyCopyWith<$Res> implements $BridgeAcpInstallStateCopyWith<$Res> {
  factory $BridgeAcpInstallState_ReadyCopyWith(BridgeAcpInstallState_Ready value, $Res Function(BridgeAcpInstallState_Ready) _then) = _$BridgeAcpInstallState_ReadyCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeAcpInstalledServer server
});




}
/// @nodoc
class _$BridgeAcpInstallState_ReadyCopyWithImpl<$Res>
    implements $BridgeAcpInstallState_ReadyCopyWith<$Res> {
  _$BridgeAcpInstallState_ReadyCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallState_Ready _self;
  final $Res Function(BridgeAcpInstallState_Ready) _then;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? server = null,}) {
  return _then(BridgeAcpInstallState_Ready(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,server: null == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstalledServer,
  ));
}


}

/// @nodoc


class BridgeAcpInstallState_Cancelling extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Cancelling({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallState_CancellingCopyWith<BridgeAcpInstallState_Cancelling> get copyWith => _$BridgeAcpInstallState_CancellingCopyWithImpl<BridgeAcpInstallState_Cancelling>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Cancelling&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}

@override
String toString() {
    return 'BridgeAcpInstallState.cancelling(operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallState_CancellingCopyWith<$Res> implements $BridgeAcpInstallStateCopyWith<$Res> {
  factory $BridgeAcpInstallState_CancellingCopyWith(BridgeAcpInstallState_Cancelling value, $Res Function(BridgeAcpInstallState_Cancelling) _then) = _$BridgeAcpInstallState_CancellingCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BridgeAcpInstallState_CancellingCopyWithImpl<$Res>
    implements $BridgeAcpInstallState_CancellingCopyWith<$Res> {
  _$BridgeAcpInstallState_CancellingCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallState_Cancelling _self;
  final $Res Function(BridgeAcpInstallState_Cancelling) _then;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BridgeAcpInstallState_Cancelling(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpInstallState_Cancelled extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Cancelled({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallState_CancelledCopyWith<BridgeAcpInstallState_Cancelled> get copyWith => _$BridgeAcpInstallState_CancelledCopyWithImpl<BridgeAcpInstallState_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Cancelled&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}

@override
String toString() {
    return 'BridgeAcpInstallState.cancelled(operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallState_CancelledCopyWith<$Res> implements $BridgeAcpInstallStateCopyWith<$Res> {
  factory $BridgeAcpInstallState_CancelledCopyWith(BridgeAcpInstallState_Cancelled value, $Res Function(BridgeAcpInstallState_Cancelled) _then) = _$BridgeAcpInstallState_CancelledCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BridgeAcpInstallState_CancelledCopyWithImpl<$Res>
    implements $BridgeAcpInstallState_CancelledCopyWith<$Res> {
  _$BridgeAcpInstallState_CancelledCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallState_Cancelled _self;
  final $Res Function(BridgeAcpInstallState_Cancelled) _then;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BridgeAcpInstallState_Cancelled(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpInstallState_Failed extends BridgeAcpInstallState {
  const BridgeAcpInstallState_Failed({required this.operationId, required this.failure}): super._();


 final  String operationId;
 final  BridgeAcpInstallFailure failure;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallState_FailedCopyWith<BridgeAcpInstallState_Failed> get copyWith => _$BridgeAcpInstallState_FailedCopyWithImpl<BridgeAcpInstallState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallState_Failed&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,failure);
}

@override
String toString() {
    return 'BridgeAcpInstallState.failed(operationId: $operationId, failure: $failure)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallState_FailedCopyWith<$Res> implements $BridgeAcpInstallStateCopyWith<$Res> {
  factory $BridgeAcpInstallState_FailedCopyWith(BridgeAcpInstallState_Failed value, $Res Function(BridgeAcpInstallState_Failed) _then) = _$BridgeAcpInstallState_FailedCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeAcpInstallFailure failure
});




}
/// @nodoc
class _$BridgeAcpInstallState_FailedCopyWithImpl<$Res>
    implements $BridgeAcpInstallState_FailedCopyWith<$Res> {
  _$BridgeAcpInstallState_FailedCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallState_Failed _self;
  final $Res Function(BridgeAcpInstallState_Failed) _then;

/// Create a copy of BridgeAcpInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? failure = null,}) {
  return _then(BridgeAcpInstallState_Failed(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallFailure,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpInstallUpdateState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallUpdateState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpInstallUpdateState()';
}


}

/// @nodoc
class $BridgeAcpInstallUpdateStateCopyWith<$Res>  {
$BridgeAcpInstallUpdateStateCopyWith(BridgeAcpInstallUpdateState _, $Res Function(BridgeAcpInstallUpdateState) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpInstallUpdateState].
extension BridgeAcpInstallUpdateStatePatterns on BridgeAcpInstallUpdateState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpInstallUpdateState_Idle value)?  idle,TResult Function( BridgeAcpInstallUpdateState_Checking value)?  checking,TResult Function( BridgeAcpInstallUpdateState_UpToDate value)?  upToDate,TResult Function( BridgeAcpInstallUpdateState_UpdateAvailable value)?  updateAvailable,TResult Function( BridgeAcpInstallUpdateState_IncompatibleMajor value)?  incompatibleMajor,TResult Function( BridgeAcpInstallUpdateState_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpInstallUpdateState_Idle() when idle != null:
return idle(_that);case BridgeAcpInstallUpdateState_Checking() when checking != null:
return checking(_that);case BridgeAcpInstallUpdateState_UpToDate() when upToDate != null:
return upToDate(_that);case BridgeAcpInstallUpdateState_UpdateAvailable() when updateAvailable != null:
return updateAvailable(_that);case BridgeAcpInstallUpdateState_IncompatibleMajor() when incompatibleMajor != null:
return incompatibleMajor(_that);case BridgeAcpInstallUpdateState_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpInstallUpdateState_Idle value)  idle,required TResult Function( BridgeAcpInstallUpdateState_Checking value)  checking,required TResult Function( BridgeAcpInstallUpdateState_UpToDate value)  upToDate,required TResult Function( BridgeAcpInstallUpdateState_UpdateAvailable value)  updateAvailable,required TResult Function( BridgeAcpInstallUpdateState_IncompatibleMajor value)  incompatibleMajor,required TResult Function( BridgeAcpInstallUpdateState_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeAcpInstallUpdateState_Idle():
return idle(_that);case BridgeAcpInstallUpdateState_Checking():
return checking(_that);case BridgeAcpInstallUpdateState_UpToDate():
return upToDate(_that);case BridgeAcpInstallUpdateState_UpdateAvailable():
return updateAvailable(_that);case BridgeAcpInstallUpdateState_IncompatibleMajor():
return incompatibleMajor(_that);case BridgeAcpInstallUpdateState_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpInstallUpdateState_Idle value)?  idle,TResult? Function( BridgeAcpInstallUpdateState_Checking value)?  checking,TResult? Function( BridgeAcpInstallUpdateState_UpToDate value)?  upToDate,TResult? Function( BridgeAcpInstallUpdateState_UpdateAvailable value)?  updateAvailable,TResult? Function( BridgeAcpInstallUpdateState_IncompatibleMajor value)?  incompatibleMajor,TResult? Function( BridgeAcpInstallUpdateState_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeAcpInstallUpdateState_Idle() when idle != null:
return idle(_that);case BridgeAcpInstallUpdateState_Checking() when checking != null:
return checking(_that);case BridgeAcpInstallUpdateState_UpToDate() when upToDate != null:
return upToDate(_that);case BridgeAcpInstallUpdateState_UpdateAvailable() when updateAvailable != null:
return updateAvailable(_that);case BridgeAcpInstallUpdateState_IncompatibleMajor() when incompatibleMajor != null:
return incompatibleMajor(_that);case BridgeAcpInstallUpdateState_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  checking,TResult Function( PlatformInt64 checkedAt,  String latestVersion)?  upToDate,TResult Function( PlatformInt64 checkedAt,  BridgeAcpInstallRelease latest)?  updateAvailable,TResult Function( PlatformInt64 checkedAt,  String latestVersion)?  incompatibleMajor,TResult Function( PlatformInt64 checkedAt,  BridgeAcpInstallFailure failure)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpInstallUpdateState_Idle() when idle != null:
return idle();case BridgeAcpInstallUpdateState_Checking() when checking != null:
return checking();case BridgeAcpInstallUpdateState_UpToDate() when upToDate != null:
return upToDate(_that.checkedAt,_that.latestVersion);case BridgeAcpInstallUpdateState_UpdateAvailable() when updateAvailable != null:
return updateAvailable(_that.checkedAt,_that.latest);case BridgeAcpInstallUpdateState_IncompatibleMajor() when incompatibleMajor != null:
return incompatibleMajor(_that.checkedAt,_that.latestVersion);case BridgeAcpInstallUpdateState_Failed() when failed != null:
return failed(_that.checkedAt,_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  checking,required TResult Function( PlatformInt64 checkedAt,  String latestVersion)  upToDate,required TResult Function( PlatformInt64 checkedAt,  BridgeAcpInstallRelease latest)  updateAvailable,required TResult Function( PlatformInt64 checkedAt,  String latestVersion)  incompatibleMajor,required TResult Function( PlatformInt64 checkedAt,  BridgeAcpInstallFailure failure)  failed,}) {final _that = this;
switch (_that) {
case BridgeAcpInstallUpdateState_Idle():
return idle();case BridgeAcpInstallUpdateState_Checking():
return checking();case BridgeAcpInstallUpdateState_UpToDate():
return upToDate(_that.checkedAt,_that.latestVersion);case BridgeAcpInstallUpdateState_UpdateAvailable():
return updateAvailable(_that.checkedAt,_that.latest);case BridgeAcpInstallUpdateState_IncompatibleMajor():
return incompatibleMajor(_that.checkedAt,_that.latestVersion);case BridgeAcpInstallUpdateState_Failed():
return failed(_that.checkedAt,_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  checking,TResult? Function( PlatformInt64 checkedAt,  String latestVersion)?  upToDate,TResult? Function( PlatformInt64 checkedAt,  BridgeAcpInstallRelease latest)?  updateAvailable,TResult? Function( PlatformInt64 checkedAt,  String latestVersion)?  incompatibleMajor,TResult? Function( PlatformInt64 checkedAt,  BridgeAcpInstallFailure failure)?  failed,}) {final _that = this;
switch (_that) {
case BridgeAcpInstallUpdateState_Idle() when idle != null:
return idle();case BridgeAcpInstallUpdateState_Checking() when checking != null:
return checking();case BridgeAcpInstallUpdateState_UpToDate() when upToDate != null:
return upToDate(_that.checkedAt,_that.latestVersion);case BridgeAcpInstallUpdateState_UpdateAvailable() when updateAvailable != null:
return updateAvailable(_that.checkedAt,_that.latest);case BridgeAcpInstallUpdateState_IncompatibleMajor() when incompatibleMajor != null:
return incompatibleMajor(_that.checkedAt,_that.latestVersion);case BridgeAcpInstallUpdateState_Failed() when failed != null:
return failed(_that.checkedAt,_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpInstallUpdateState_Idle extends BridgeAcpInstallUpdateState {
  const BridgeAcpInstallUpdateState_Idle(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallUpdateState_Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpInstallUpdateState.idle()';
}


}




/// @nodoc


class BridgeAcpInstallUpdateState_Checking extends BridgeAcpInstallUpdateState {
  const BridgeAcpInstallUpdateState_Checking(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallUpdateState_Checking);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpInstallUpdateState.checking()';
}


}




/// @nodoc


class BridgeAcpInstallUpdateState_UpToDate extends BridgeAcpInstallUpdateState {
  const BridgeAcpInstallUpdateState_UpToDate({required this.checkedAt, required this.latestVersion}): super._();


 final  PlatformInt64 checkedAt;
 final  String latestVersion;

/// Create a copy of BridgeAcpInstallUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallUpdateState_UpToDateCopyWith<BridgeAcpInstallUpdateState_UpToDate> get copyWith => _$BridgeAcpInstallUpdateState_UpToDateCopyWithImpl<BridgeAcpInstallUpdateState_UpToDate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallUpdateState_UpToDate&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.latestVersion, latestVersion) || other.latestVersion == latestVersion));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,latestVersion);
}

@override
String toString() {
    return 'BridgeAcpInstallUpdateState.upToDate(checkedAt: $checkedAt, latestVersion: $latestVersion)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallUpdateState_UpToDateCopyWith<$Res> implements $BridgeAcpInstallUpdateStateCopyWith<$Res> {
  factory $BridgeAcpInstallUpdateState_UpToDateCopyWith(BridgeAcpInstallUpdateState_UpToDate value, $Res Function(BridgeAcpInstallUpdateState_UpToDate) _then) = _$BridgeAcpInstallUpdateState_UpToDateCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 checkedAt, String latestVersion
});




}
/// @nodoc
class _$BridgeAcpInstallUpdateState_UpToDateCopyWithImpl<$Res>
    implements $BridgeAcpInstallUpdateState_UpToDateCopyWith<$Res> {
  _$BridgeAcpInstallUpdateState_UpToDateCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallUpdateState_UpToDate _self;
  final $Res Function(BridgeAcpInstallUpdateState_UpToDate) _then;

/// Create a copy of BridgeAcpInstallUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? latestVersion = null,}) {
  return _then(BridgeAcpInstallUpdateState_UpToDate(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,latestVersion: null == latestVersion ? _self.latestVersion : latestVersion // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpInstallUpdateState_UpdateAvailable extends BridgeAcpInstallUpdateState {
  const BridgeAcpInstallUpdateState_UpdateAvailable({required this.checkedAt, required this.latest}): super._();


 final  PlatformInt64 checkedAt;
 final  BridgeAcpInstallRelease latest;

/// Create a copy of BridgeAcpInstallUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallUpdateState_UpdateAvailableCopyWith<BridgeAcpInstallUpdateState_UpdateAvailable> get copyWith => _$BridgeAcpInstallUpdateState_UpdateAvailableCopyWithImpl<BridgeAcpInstallUpdateState_UpdateAvailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallUpdateState_UpdateAvailable&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.latest, latest) || other.latest == latest));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,latest);
}

@override
String toString() {
    return 'BridgeAcpInstallUpdateState.updateAvailable(checkedAt: $checkedAt, latest: $latest)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallUpdateState_UpdateAvailableCopyWith<$Res> implements $BridgeAcpInstallUpdateStateCopyWith<$Res> {
  factory $BridgeAcpInstallUpdateState_UpdateAvailableCopyWith(BridgeAcpInstallUpdateState_UpdateAvailable value, $Res Function(BridgeAcpInstallUpdateState_UpdateAvailable) _then) = _$BridgeAcpInstallUpdateState_UpdateAvailableCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 checkedAt, BridgeAcpInstallRelease latest
});




}
/// @nodoc
class _$BridgeAcpInstallUpdateState_UpdateAvailableCopyWithImpl<$Res>
    implements $BridgeAcpInstallUpdateState_UpdateAvailableCopyWith<$Res> {
  _$BridgeAcpInstallUpdateState_UpdateAvailableCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallUpdateState_UpdateAvailable _self;
  final $Res Function(BridgeAcpInstallUpdateState_UpdateAvailable) _then;

/// Create a copy of BridgeAcpInstallUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? latest = null,}) {
  return _then(BridgeAcpInstallUpdateState_UpdateAvailable(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,latest: null == latest ? _self.latest : latest // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallRelease,
  ));
}


}

/// @nodoc


class BridgeAcpInstallUpdateState_IncompatibleMajor extends BridgeAcpInstallUpdateState {
  const BridgeAcpInstallUpdateState_IncompatibleMajor({required this.checkedAt, required this.latestVersion}): super._();


 final  PlatformInt64 checkedAt;
 final  String latestVersion;

/// Create a copy of BridgeAcpInstallUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallUpdateState_IncompatibleMajorCopyWith<BridgeAcpInstallUpdateState_IncompatibleMajor> get copyWith => _$BridgeAcpInstallUpdateState_IncompatibleMajorCopyWithImpl<BridgeAcpInstallUpdateState_IncompatibleMajor>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallUpdateState_IncompatibleMajor&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.latestVersion, latestVersion) || other.latestVersion == latestVersion));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,latestVersion);
}

@override
String toString() {
    return 'BridgeAcpInstallUpdateState.incompatibleMajor(checkedAt: $checkedAt, latestVersion: $latestVersion)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallUpdateState_IncompatibleMajorCopyWith<$Res> implements $BridgeAcpInstallUpdateStateCopyWith<$Res> {
  factory $BridgeAcpInstallUpdateState_IncompatibleMajorCopyWith(BridgeAcpInstallUpdateState_IncompatibleMajor value, $Res Function(BridgeAcpInstallUpdateState_IncompatibleMajor) _then) = _$BridgeAcpInstallUpdateState_IncompatibleMajorCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 checkedAt, String latestVersion
});




}
/// @nodoc
class _$BridgeAcpInstallUpdateState_IncompatibleMajorCopyWithImpl<$Res>
    implements $BridgeAcpInstallUpdateState_IncompatibleMajorCopyWith<$Res> {
  _$BridgeAcpInstallUpdateState_IncompatibleMajorCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallUpdateState_IncompatibleMajor _self;
  final $Res Function(BridgeAcpInstallUpdateState_IncompatibleMajor) _then;

/// Create a copy of BridgeAcpInstallUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? latestVersion = null,}) {
  return _then(BridgeAcpInstallUpdateState_IncompatibleMajor(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,latestVersion: null == latestVersion ? _self.latestVersion : latestVersion // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpInstallUpdateState_Failed extends BridgeAcpInstallUpdateState {
  const BridgeAcpInstallUpdateState_Failed({required this.checkedAt, required this.failure}): super._();


 final  PlatformInt64 checkedAt;
 final  BridgeAcpInstallFailure failure;

/// Create a copy of BridgeAcpInstallUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpInstallUpdateState_FailedCopyWith<BridgeAcpInstallUpdateState_Failed> get copyWith => _$BridgeAcpInstallUpdateState_FailedCopyWithImpl<BridgeAcpInstallUpdateState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpInstallUpdateState_Failed&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,failure);
}

@override
String toString() {
    return 'BridgeAcpInstallUpdateState.failed(checkedAt: $checkedAt, failure: $failure)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpInstallUpdateState_FailedCopyWith<$Res> implements $BridgeAcpInstallUpdateStateCopyWith<$Res> {
  factory $BridgeAcpInstallUpdateState_FailedCopyWith(BridgeAcpInstallUpdateState_Failed value, $Res Function(BridgeAcpInstallUpdateState_Failed) _then) = _$BridgeAcpInstallUpdateState_FailedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 checkedAt, BridgeAcpInstallFailure failure
});




}
/// @nodoc
class _$BridgeAcpInstallUpdateState_FailedCopyWithImpl<$Res>
    implements $BridgeAcpInstallUpdateState_FailedCopyWith<$Res> {
  _$BridgeAcpInstallUpdateState_FailedCopyWithImpl(this._self, this._then);

  final BridgeAcpInstallUpdateState_Failed _self;
  final $Res Function(BridgeAcpInstallUpdateState_Failed) _then;

/// Create a copy of BridgeAcpInstallUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? failure = null,}) {
  return _then(BridgeAcpInstallUpdateState_Failed(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallFailure,
  ));
}


}

// dart format on
