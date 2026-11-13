// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'updater.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeUpdatePreparationResult {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatePreparationResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeUpdatePreparationResult()';
}


}

/// @nodoc
class $BridgeUpdatePreparationResultCopyWith<$Res>  {
$BridgeUpdatePreparationResultCopyWith(BridgeUpdatePreparationResult _, $Res Function(BridgeUpdatePreparationResult) __);
}


/// Adds pattern-matching-related methods to [BridgeUpdatePreparationResult].
extension BridgeUpdatePreparationResultPatterns on BridgeUpdatePreparationResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeUpdatePreparationResult_Ready value)?  ready,TResult Function( BridgeUpdatePreparationResult_Cancelled value)?  cancelled,TResult Function( BridgeUpdatePreparationResult_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeUpdatePreparationResult_Ready() when ready != null:
return ready(_that);case BridgeUpdatePreparationResult_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeUpdatePreparationResult_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeUpdatePreparationResult_Ready value)  ready,required TResult Function( BridgeUpdatePreparationResult_Cancelled value)  cancelled,required TResult Function( BridgeUpdatePreparationResult_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeUpdatePreparationResult_Ready():
return ready(_that);case BridgeUpdatePreparationResult_Cancelled():
return cancelled(_that);case BridgeUpdatePreparationResult_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeUpdatePreparationResult_Ready value)?  ready,TResult? Function( BridgeUpdatePreparationResult_Cancelled value)?  cancelled,TResult? Function( BridgeUpdatePreparationResult_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeUpdatePreparationResult_Ready() when ready != null:
return ready(_that);case BridgeUpdatePreparationResult_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeUpdatePreparationResult_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String version)?  ready,TResult Function()?  cancelled,TResult Function( BridgeStateError error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeUpdatePreparationResult_Ready() when ready != null:
return ready(_that.version);case BridgeUpdatePreparationResult_Cancelled() when cancelled != null:
return cancelled();case BridgeUpdatePreparationResult_Failed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String version)  ready,required TResult Function()  cancelled,required TResult Function( BridgeStateError error)  failed,}) {final _that = this;
switch (_that) {
case BridgeUpdatePreparationResult_Ready():
return ready(_that.version);case BridgeUpdatePreparationResult_Cancelled():
return cancelled();case BridgeUpdatePreparationResult_Failed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String version)?  ready,TResult? Function()?  cancelled,TResult? Function( BridgeStateError error)?  failed,}) {final _that = this;
switch (_that) {
case BridgeUpdatePreparationResult_Ready() when ready != null:
return ready(_that.version);case BridgeUpdatePreparationResult_Cancelled() when cancelled != null:
return cancelled();case BridgeUpdatePreparationResult_Failed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeUpdatePreparationResult_Ready extends BridgeUpdatePreparationResult {
  const BridgeUpdatePreparationResult_Ready({required this.version}): super._();


 final  String version;

/// Create a copy of BridgeUpdatePreparationResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatePreparationResult_ReadyCopyWith<BridgeUpdatePreparationResult_Ready> get copyWith => _$BridgeUpdatePreparationResult_ReadyCopyWithImpl<BridgeUpdatePreparationResult_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatePreparationResult_Ready&&(identical(other.version, version) || other.version == version));
}


@override
int get hashCode {
    return Object.hash(runtimeType,version);
}

@override
String toString() {
    return 'BridgeUpdatePreparationResult.ready(version: $version)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatePreparationResult_ReadyCopyWith<$Res> implements $BridgeUpdatePreparationResultCopyWith<$Res> {
  factory $BridgeUpdatePreparationResult_ReadyCopyWith(BridgeUpdatePreparationResult_Ready value, $Res Function(BridgeUpdatePreparationResult_Ready) _then) = _$BridgeUpdatePreparationResult_ReadyCopyWithImpl;
@useResult
$Res call({
 String version
});




}
/// @nodoc
class _$BridgeUpdatePreparationResult_ReadyCopyWithImpl<$Res>
    implements $BridgeUpdatePreparationResult_ReadyCopyWith<$Res> {
  _$BridgeUpdatePreparationResult_ReadyCopyWithImpl(this._self, this._then);

  final BridgeUpdatePreparationResult_Ready _self;
  final $Res Function(BridgeUpdatePreparationResult_Ready) _then;

/// Create a copy of BridgeUpdatePreparationResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? version = null,}) {
  return _then(BridgeUpdatePreparationResult_Ready(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeUpdatePreparationResult_Cancelled extends BridgeUpdatePreparationResult {
  const BridgeUpdatePreparationResult_Cancelled(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatePreparationResult_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeUpdatePreparationResult.cancelled()';
}


}




/// @nodoc


class BridgeUpdatePreparationResult_Failed extends BridgeUpdatePreparationResult {
  const BridgeUpdatePreparationResult_Failed({required this.error}): super._();


 final  BridgeStateError error;

/// Create a copy of BridgeUpdatePreparationResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatePreparationResult_FailedCopyWith<BridgeUpdatePreparationResult_Failed> get copyWith => _$BridgeUpdatePreparationResult_FailedCopyWithImpl<BridgeUpdatePreparationResult_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatePreparationResult_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeUpdatePreparationResult.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatePreparationResult_FailedCopyWith<$Res> implements $BridgeUpdatePreparationResultCopyWith<$Res> {
  factory $BridgeUpdatePreparationResult_FailedCopyWith(BridgeUpdatePreparationResult_Failed value, $Res Function(BridgeUpdatePreparationResult_Failed) _then) = _$BridgeUpdatePreparationResult_FailedCopyWithImpl;
@useResult
$Res call({
 BridgeStateError error
});




}
/// @nodoc
class _$BridgeUpdatePreparationResult_FailedCopyWithImpl<$Res>
    implements $BridgeUpdatePreparationResult_FailedCopyWith<$Res> {
  _$BridgeUpdatePreparationResult_FailedCopyWithImpl(this._self, this._then);

  final BridgeUpdatePreparationResult_Failed _self;
  final $Res Function(BridgeUpdatePreparationResult_Failed) _then;

/// Create a copy of BridgeUpdatePreparationResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeUpdatePreparationResult_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeStateError,
  ));
}


}

/// @nodoc
mixin _$BridgeUpdaterActivity {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as BridgeUpdaterActivity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as BridgeUpdaterActivity;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as BridgeUpdaterActivity;
  return 'BridgeUpdaterActivity(field0: ${_this.field0})';
}


}

/// @nodoc
class $BridgeUpdaterActivityCopyWith<$Res>  {
$BridgeUpdaterActivityCopyWith(BridgeUpdaterActivity _, $Res Function(BridgeUpdaterActivity) __);
}


/// Adds pattern-matching-related methods to [BridgeUpdaterActivity].
extension BridgeUpdaterActivityPatterns on BridgeUpdaterActivity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeUpdaterActivity_Disabled value)?  disabled,TResult Function( BridgeUpdaterActivity_Idle value)?  idle,TResult Function( BridgeUpdaterActivity_Checking value)?  checking,TResult Function( BridgeUpdaterActivity_UpToDate value)?  upToDate,TResult Function( BridgeUpdaterActivity_Available value)?  available,TResult Function( BridgeUpdaterActivity_Downloading value)?  downloading,TResult Function( BridgeUpdaterActivity_Verifying value)?  verifying,TResult Function( BridgeUpdaterActivity_Ready value)?  ready,TResult Function( BridgeUpdaterActivity_InstallerLaunched value)?  installerLaunched,TResult Function( BridgeUpdaterActivity_CheckFailed value)?  checkFailed,TResult Function( BridgeUpdaterActivity_InstallFailed value)?  installFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeUpdaterActivity_Disabled() when disabled != null:
return disabled(_that);case BridgeUpdaterActivity_Idle() when idle != null:
return idle(_that);case BridgeUpdaterActivity_Checking() when checking != null:
return checking(_that);case BridgeUpdaterActivity_UpToDate() when upToDate != null:
return upToDate(_that);case BridgeUpdaterActivity_Available() when available != null:
return available(_that);case BridgeUpdaterActivity_Downloading() when downloading != null:
return downloading(_that);case BridgeUpdaterActivity_Verifying() when verifying != null:
return verifying(_that);case BridgeUpdaterActivity_Ready() when ready != null:
return ready(_that);case BridgeUpdaterActivity_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that);case BridgeUpdaterActivity_CheckFailed() when checkFailed != null:
return checkFailed(_that);case BridgeUpdaterActivity_InstallFailed() when installFailed != null:
return installFailed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeUpdaterActivity_Disabled value)  disabled,required TResult Function( BridgeUpdaterActivity_Idle value)  idle,required TResult Function( BridgeUpdaterActivity_Checking value)  checking,required TResult Function( BridgeUpdaterActivity_UpToDate value)  upToDate,required TResult Function( BridgeUpdaterActivity_Available value)  available,required TResult Function( BridgeUpdaterActivity_Downloading value)  downloading,required TResult Function( BridgeUpdaterActivity_Verifying value)  verifying,required TResult Function( BridgeUpdaterActivity_Ready value)  ready,required TResult Function( BridgeUpdaterActivity_InstallerLaunched value)  installerLaunched,required TResult Function( BridgeUpdaterActivity_CheckFailed value)  checkFailed,required TResult Function( BridgeUpdaterActivity_InstallFailed value)  installFailed,}){
final _that = this;
switch (_that) {
case BridgeUpdaterActivity_Disabled():
return disabled(_that);case BridgeUpdaterActivity_Idle():
return idle(_that);case BridgeUpdaterActivity_Checking():
return checking(_that);case BridgeUpdaterActivity_UpToDate():
return upToDate(_that);case BridgeUpdaterActivity_Available():
return available(_that);case BridgeUpdaterActivity_Downloading():
return downloading(_that);case BridgeUpdaterActivity_Verifying():
return verifying(_that);case BridgeUpdaterActivity_Ready():
return ready(_that);case BridgeUpdaterActivity_InstallerLaunched():
return installerLaunched(_that);case BridgeUpdaterActivity_CheckFailed():
return checkFailed(_that);case BridgeUpdaterActivity_InstallFailed():
return installFailed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeUpdaterActivity_Disabled value)?  disabled,TResult? Function( BridgeUpdaterActivity_Idle value)?  idle,TResult? Function( BridgeUpdaterActivity_Checking value)?  checking,TResult? Function( BridgeUpdaterActivity_UpToDate value)?  upToDate,TResult? Function( BridgeUpdaterActivity_Available value)?  available,TResult? Function( BridgeUpdaterActivity_Downloading value)?  downloading,TResult? Function( BridgeUpdaterActivity_Verifying value)?  verifying,TResult? Function( BridgeUpdaterActivity_Ready value)?  ready,TResult? Function( BridgeUpdaterActivity_InstallerLaunched value)?  installerLaunched,TResult? Function( BridgeUpdaterActivity_CheckFailed value)?  checkFailed,TResult? Function( BridgeUpdaterActivity_InstallFailed value)?  installFailed,}){
final _that = this;
switch (_that) {
case BridgeUpdaterActivity_Disabled() when disabled != null:
return disabled(_that);case BridgeUpdaterActivity_Idle() when idle != null:
return idle(_that);case BridgeUpdaterActivity_Checking() when checking != null:
return checking(_that);case BridgeUpdaterActivity_UpToDate() when upToDate != null:
return upToDate(_that);case BridgeUpdaterActivity_Available() when available != null:
return available(_that);case BridgeUpdaterActivity_Downloading() when downloading != null:
return downloading(_that);case BridgeUpdaterActivity_Verifying() when verifying != null:
return verifying(_that);case BridgeUpdaterActivity_Ready() when ready != null:
return ready(_that);case BridgeUpdaterActivity_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that);case BridgeUpdaterActivity_CheckFailed() when checkFailed != null:
return checkFailed(_that);case BridgeUpdaterActivity_InstallFailed() when installFailed != null:
return installFailed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeDisabledUpdaterState field0)?  disabled,TResult Function( BridgeIdleUpdaterState field0)?  idle,TResult Function( BridgeCheckingUpdaterState field0)?  checking,TResult Function( BridgeUpToDateUpdaterState field0)?  upToDate,TResult Function( BridgeAvailableUpdaterState field0)?  available,TResult Function( BridgeDownloadingUpdaterState field0)?  downloading,TResult Function( BridgeVerifyingUpdaterState field0)?  verifying,TResult Function( BridgeReadyUpdaterState field0)?  ready,TResult Function( BridgeInstallerLaunchedUpdaterState field0)?  installerLaunched,TResult Function( BridgeCheckFailedUpdaterState field0)?  checkFailed,TResult Function( BridgeInstallFailedUpdaterState field0)?  installFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeUpdaterActivity_Disabled() when disabled != null:
return disabled(_that.field0);case BridgeUpdaterActivity_Idle() when idle != null:
return idle(_that.field0);case BridgeUpdaterActivity_Checking() when checking != null:
return checking(_that.field0);case BridgeUpdaterActivity_UpToDate() when upToDate != null:
return upToDate(_that.field0);case BridgeUpdaterActivity_Available() when available != null:
return available(_that.field0);case BridgeUpdaterActivity_Downloading() when downloading != null:
return downloading(_that.field0);case BridgeUpdaterActivity_Verifying() when verifying != null:
return verifying(_that.field0);case BridgeUpdaterActivity_Ready() when ready != null:
return ready(_that.field0);case BridgeUpdaterActivity_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that.field0);case BridgeUpdaterActivity_CheckFailed() when checkFailed != null:
return checkFailed(_that.field0);case BridgeUpdaterActivity_InstallFailed() when installFailed != null:
return installFailed(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeDisabledUpdaterState field0)  disabled,required TResult Function( BridgeIdleUpdaterState field0)  idle,required TResult Function( BridgeCheckingUpdaterState field0)  checking,required TResult Function( BridgeUpToDateUpdaterState field0)  upToDate,required TResult Function( BridgeAvailableUpdaterState field0)  available,required TResult Function( BridgeDownloadingUpdaterState field0)  downloading,required TResult Function( BridgeVerifyingUpdaterState field0)  verifying,required TResult Function( BridgeReadyUpdaterState field0)  ready,required TResult Function( BridgeInstallerLaunchedUpdaterState field0)  installerLaunched,required TResult Function( BridgeCheckFailedUpdaterState field0)  checkFailed,required TResult Function( BridgeInstallFailedUpdaterState field0)  installFailed,}) {final _that = this;
switch (_that) {
case BridgeUpdaterActivity_Disabled():
return disabled(_that.field0);case BridgeUpdaterActivity_Idle():
return idle(_that.field0);case BridgeUpdaterActivity_Checking():
return checking(_that.field0);case BridgeUpdaterActivity_UpToDate():
return upToDate(_that.field0);case BridgeUpdaterActivity_Available():
return available(_that.field0);case BridgeUpdaterActivity_Downloading():
return downloading(_that.field0);case BridgeUpdaterActivity_Verifying():
return verifying(_that.field0);case BridgeUpdaterActivity_Ready():
return ready(_that.field0);case BridgeUpdaterActivity_InstallerLaunched():
return installerLaunched(_that.field0);case BridgeUpdaterActivity_CheckFailed():
return checkFailed(_that.field0);case BridgeUpdaterActivity_InstallFailed():
return installFailed(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeDisabledUpdaterState field0)?  disabled,TResult? Function( BridgeIdleUpdaterState field0)?  idle,TResult? Function( BridgeCheckingUpdaterState field0)?  checking,TResult? Function( BridgeUpToDateUpdaterState field0)?  upToDate,TResult? Function( BridgeAvailableUpdaterState field0)?  available,TResult? Function( BridgeDownloadingUpdaterState field0)?  downloading,TResult? Function( BridgeVerifyingUpdaterState field0)?  verifying,TResult? Function( BridgeReadyUpdaterState field0)?  ready,TResult? Function( BridgeInstallerLaunchedUpdaterState field0)?  installerLaunched,TResult? Function( BridgeCheckFailedUpdaterState field0)?  checkFailed,TResult? Function( BridgeInstallFailedUpdaterState field0)?  installFailed,}) {final _that = this;
switch (_that) {
case BridgeUpdaterActivity_Disabled() when disabled != null:
return disabled(_that.field0);case BridgeUpdaterActivity_Idle() when idle != null:
return idle(_that.field0);case BridgeUpdaterActivity_Checking() when checking != null:
return checking(_that.field0);case BridgeUpdaterActivity_UpToDate() when upToDate != null:
return upToDate(_that.field0);case BridgeUpdaterActivity_Available() when available != null:
return available(_that.field0);case BridgeUpdaterActivity_Downloading() when downloading != null:
return downloading(_that.field0);case BridgeUpdaterActivity_Verifying() when verifying != null:
return verifying(_that.field0);case BridgeUpdaterActivity_Ready() when ready != null:
return ready(_that.field0);case BridgeUpdaterActivity_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that.field0);case BridgeUpdaterActivity_CheckFailed() when checkFailed != null:
return checkFailed(_that.field0);case BridgeUpdaterActivity_InstallFailed() when installFailed != null:
return installFailed(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class BridgeUpdaterActivity_Disabled extends BridgeUpdaterActivity {
  const BridgeUpdaterActivity_Disabled(this.field0): super._();


@override final  BridgeDisabledUpdaterState field0;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdaterActivity_DisabledCopyWith<BridgeUpdaterActivity_Disabled> get copyWith => _$BridgeUpdaterActivity_DisabledCopyWithImpl<BridgeUpdaterActivity_Disabled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity_Disabled&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeUpdaterActivity.disabled(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdaterActivity_DisabledCopyWith<$Res> implements $BridgeUpdaterActivityCopyWith<$Res> {
  factory $BridgeUpdaterActivity_DisabledCopyWith(BridgeUpdaterActivity_Disabled value, $Res Function(BridgeUpdaterActivity_Disabled) _then) = _$BridgeUpdaterActivity_DisabledCopyWithImpl;
@useResult
$Res call({
 BridgeDisabledUpdaterState field0
});




}
/// @nodoc
class _$BridgeUpdaterActivity_DisabledCopyWithImpl<$Res>
    implements $BridgeUpdaterActivity_DisabledCopyWith<$Res> {
  _$BridgeUpdaterActivity_DisabledCopyWithImpl(this._self, this._then);

  final BridgeUpdaterActivity_Disabled _self;
  final $Res Function(BridgeUpdaterActivity_Disabled) _then;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeUpdaterActivity_Disabled(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeDisabledUpdaterState,
  ));
}


}

/// @nodoc


class BridgeUpdaterActivity_Idle extends BridgeUpdaterActivity {
  const BridgeUpdaterActivity_Idle(this.field0): super._();


@override final  BridgeIdleUpdaterState field0;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdaterActivity_IdleCopyWith<BridgeUpdaterActivity_Idle> get copyWith => _$BridgeUpdaterActivity_IdleCopyWithImpl<BridgeUpdaterActivity_Idle>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity_Idle&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeUpdaterActivity.idle(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdaterActivity_IdleCopyWith<$Res> implements $BridgeUpdaterActivityCopyWith<$Res> {
  factory $BridgeUpdaterActivity_IdleCopyWith(BridgeUpdaterActivity_Idle value, $Res Function(BridgeUpdaterActivity_Idle) _then) = _$BridgeUpdaterActivity_IdleCopyWithImpl;
@useResult
$Res call({
 BridgeIdleUpdaterState field0
});




}
/// @nodoc
class _$BridgeUpdaterActivity_IdleCopyWithImpl<$Res>
    implements $BridgeUpdaterActivity_IdleCopyWith<$Res> {
  _$BridgeUpdaterActivity_IdleCopyWithImpl(this._self, this._then);

  final BridgeUpdaterActivity_Idle _self;
  final $Res Function(BridgeUpdaterActivity_Idle) _then;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeUpdaterActivity_Idle(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeIdleUpdaterState,
  ));
}


}

/// @nodoc


class BridgeUpdaterActivity_Checking extends BridgeUpdaterActivity {
  const BridgeUpdaterActivity_Checking(this.field0): super._();


@override final  BridgeCheckingUpdaterState field0;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdaterActivity_CheckingCopyWith<BridgeUpdaterActivity_Checking> get copyWith => _$BridgeUpdaterActivity_CheckingCopyWithImpl<BridgeUpdaterActivity_Checking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity_Checking&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeUpdaterActivity.checking(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdaterActivity_CheckingCopyWith<$Res> implements $BridgeUpdaterActivityCopyWith<$Res> {
  factory $BridgeUpdaterActivity_CheckingCopyWith(BridgeUpdaterActivity_Checking value, $Res Function(BridgeUpdaterActivity_Checking) _then) = _$BridgeUpdaterActivity_CheckingCopyWithImpl;
@useResult
$Res call({
 BridgeCheckingUpdaterState field0
});




}
/// @nodoc
class _$BridgeUpdaterActivity_CheckingCopyWithImpl<$Res>
    implements $BridgeUpdaterActivity_CheckingCopyWith<$Res> {
  _$BridgeUpdaterActivity_CheckingCopyWithImpl(this._self, this._then);

  final BridgeUpdaterActivity_Checking _self;
  final $Res Function(BridgeUpdaterActivity_Checking) _then;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeUpdaterActivity_Checking(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeCheckingUpdaterState,
  ));
}


}

/// @nodoc


class BridgeUpdaterActivity_UpToDate extends BridgeUpdaterActivity {
  const BridgeUpdaterActivity_UpToDate(this.field0): super._();


@override final  BridgeUpToDateUpdaterState field0;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdaterActivity_UpToDateCopyWith<BridgeUpdaterActivity_UpToDate> get copyWith => _$BridgeUpdaterActivity_UpToDateCopyWithImpl<BridgeUpdaterActivity_UpToDate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity_UpToDate&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeUpdaterActivity.upToDate(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdaterActivity_UpToDateCopyWith<$Res> implements $BridgeUpdaterActivityCopyWith<$Res> {
  factory $BridgeUpdaterActivity_UpToDateCopyWith(BridgeUpdaterActivity_UpToDate value, $Res Function(BridgeUpdaterActivity_UpToDate) _then) = _$BridgeUpdaterActivity_UpToDateCopyWithImpl;
@useResult
$Res call({
 BridgeUpToDateUpdaterState field0
});




}
/// @nodoc
class _$BridgeUpdaterActivity_UpToDateCopyWithImpl<$Res>
    implements $BridgeUpdaterActivity_UpToDateCopyWith<$Res> {
  _$BridgeUpdaterActivity_UpToDateCopyWithImpl(this._self, this._then);

  final BridgeUpdaterActivity_UpToDate _self;
  final $Res Function(BridgeUpdaterActivity_UpToDate) _then;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeUpdaterActivity_UpToDate(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeUpToDateUpdaterState,
  ));
}


}

/// @nodoc


class BridgeUpdaterActivity_Available extends BridgeUpdaterActivity {
  const BridgeUpdaterActivity_Available(this.field0): super._();


@override final  BridgeAvailableUpdaterState field0;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdaterActivity_AvailableCopyWith<BridgeUpdaterActivity_Available> get copyWith => _$BridgeUpdaterActivity_AvailableCopyWithImpl<BridgeUpdaterActivity_Available>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity_Available&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeUpdaterActivity.available(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdaterActivity_AvailableCopyWith<$Res> implements $BridgeUpdaterActivityCopyWith<$Res> {
  factory $BridgeUpdaterActivity_AvailableCopyWith(BridgeUpdaterActivity_Available value, $Res Function(BridgeUpdaterActivity_Available) _then) = _$BridgeUpdaterActivity_AvailableCopyWithImpl;
@useResult
$Res call({
 BridgeAvailableUpdaterState field0
});




}
/// @nodoc
class _$BridgeUpdaterActivity_AvailableCopyWithImpl<$Res>
    implements $BridgeUpdaterActivity_AvailableCopyWith<$Res> {
  _$BridgeUpdaterActivity_AvailableCopyWithImpl(this._self, this._then);

  final BridgeUpdaterActivity_Available _self;
  final $Res Function(BridgeUpdaterActivity_Available) _then;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeUpdaterActivity_Available(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeAvailableUpdaterState,
  ));
}


}

/// @nodoc


class BridgeUpdaterActivity_Downloading extends BridgeUpdaterActivity {
  const BridgeUpdaterActivity_Downloading(this.field0): super._();


@override final  BridgeDownloadingUpdaterState field0;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdaterActivity_DownloadingCopyWith<BridgeUpdaterActivity_Downloading> get copyWith => _$BridgeUpdaterActivity_DownloadingCopyWithImpl<BridgeUpdaterActivity_Downloading>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity_Downloading&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeUpdaterActivity.downloading(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdaterActivity_DownloadingCopyWith<$Res> implements $BridgeUpdaterActivityCopyWith<$Res> {
  factory $BridgeUpdaterActivity_DownloadingCopyWith(BridgeUpdaterActivity_Downloading value, $Res Function(BridgeUpdaterActivity_Downloading) _then) = _$BridgeUpdaterActivity_DownloadingCopyWithImpl;
@useResult
$Res call({
 BridgeDownloadingUpdaterState field0
});




}
/// @nodoc
class _$BridgeUpdaterActivity_DownloadingCopyWithImpl<$Res>
    implements $BridgeUpdaterActivity_DownloadingCopyWith<$Res> {
  _$BridgeUpdaterActivity_DownloadingCopyWithImpl(this._self, this._then);

  final BridgeUpdaterActivity_Downloading _self;
  final $Res Function(BridgeUpdaterActivity_Downloading) _then;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeUpdaterActivity_Downloading(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeDownloadingUpdaterState,
  ));
}


}

/// @nodoc


class BridgeUpdaterActivity_Verifying extends BridgeUpdaterActivity {
  const BridgeUpdaterActivity_Verifying(this.field0): super._();


@override final  BridgeVerifyingUpdaterState field0;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdaterActivity_VerifyingCopyWith<BridgeUpdaterActivity_Verifying> get copyWith => _$BridgeUpdaterActivity_VerifyingCopyWithImpl<BridgeUpdaterActivity_Verifying>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity_Verifying&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeUpdaterActivity.verifying(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdaterActivity_VerifyingCopyWith<$Res> implements $BridgeUpdaterActivityCopyWith<$Res> {
  factory $BridgeUpdaterActivity_VerifyingCopyWith(BridgeUpdaterActivity_Verifying value, $Res Function(BridgeUpdaterActivity_Verifying) _then) = _$BridgeUpdaterActivity_VerifyingCopyWithImpl;
@useResult
$Res call({
 BridgeVerifyingUpdaterState field0
});




}
/// @nodoc
class _$BridgeUpdaterActivity_VerifyingCopyWithImpl<$Res>
    implements $BridgeUpdaterActivity_VerifyingCopyWith<$Res> {
  _$BridgeUpdaterActivity_VerifyingCopyWithImpl(this._self, this._then);

  final BridgeUpdaterActivity_Verifying _self;
  final $Res Function(BridgeUpdaterActivity_Verifying) _then;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeUpdaterActivity_Verifying(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeVerifyingUpdaterState,
  ));
}


}

/// @nodoc


class BridgeUpdaterActivity_Ready extends BridgeUpdaterActivity {
  const BridgeUpdaterActivity_Ready(this.field0): super._();


@override final  BridgeReadyUpdaterState field0;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdaterActivity_ReadyCopyWith<BridgeUpdaterActivity_Ready> get copyWith => _$BridgeUpdaterActivity_ReadyCopyWithImpl<BridgeUpdaterActivity_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity_Ready&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeUpdaterActivity.ready(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdaterActivity_ReadyCopyWith<$Res> implements $BridgeUpdaterActivityCopyWith<$Res> {
  factory $BridgeUpdaterActivity_ReadyCopyWith(BridgeUpdaterActivity_Ready value, $Res Function(BridgeUpdaterActivity_Ready) _then) = _$BridgeUpdaterActivity_ReadyCopyWithImpl;
@useResult
$Res call({
 BridgeReadyUpdaterState field0
});




}
/// @nodoc
class _$BridgeUpdaterActivity_ReadyCopyWithImpl<$Res>
    implements $BridgeUpdaterActivity_ReadyCopyWith<$Res> {
  _$BridgeUpdaterActivity_ReadyCopyWithImpl(this._self, this._then);

  final BridgeUpdaterActivity_Ready _self;
  final $Res Function(BridgeUpdaterActivity_Ready) _then;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeUpdaterActivity_Ready(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeReadyUpdaterState,
  ));
}


}

/// @nodoc


class BridgeUpdaterActivity_InstallerLaunched extends BridgeUpdaterActivity {
  const BridgeUpdaterActivity_InstallerLaunched(this.field0): super._();


@override final  BridgeInstallerLaunchedUpdaterState field0;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdaterActivity_InstallerLaunchedCopyWith<BridgeUpdaterActivity_InstallerLaunched> get copyWith => _$BridgeUpdaterActivity_InstallerLaunchedCopyWithImpl<BridgeUpdaterActivity_InstallerLaunched>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity_InstallerLaunched&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeUpdaterActivity.installerLaunched(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdaterActivity_InstallerLaunchedCopyWith<$Res> implements $BridgeUpdaterActivityCopyWith<$Res> {
  factory $BridgeUpdaterActivity_InstallerLaunchedCopyWith(BridgeUpdaterActivity_InstallerLaunched value, $Res Function(BridgeUpdaterActivity_InstallerLaunched) _then) = _$BridgeUpdaterActivity_InstallerLaunchedCopyWithImpl;
@useResult
$Res call({
 BridgeInstallerLaunchedUpdaterState field0
});




}
/// @nodoc
class _$BridgeUpdaterActivity_InstallerLaunchedCopyWithImpl<$Res>
    implements $BridgeUpdaterActivity_InstallerLaunchedCopyWith<$Res> {
  _$BridgeUpdaterActivity_InstallerLaunchedCopyWithImpl(this._self, this._then);

  final BridgeUpdaterActivity_InstallerLaunched _self;
  final $Res Function(BridgeUpdaterActivity_InstallerLaunched) _then;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeUpdaterActivity_InstallerLaunched(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeInstallerLaunchedUpdaterState,
  ));
}


}

/// @nodoc


class BridgeUpdaterActivity_CheckFailed extends BridgeUpdaterActivity {
  const BridgeUpdaterActivity_CheckFailed(this.field0): super._();


@override final  BridgeCheckFailedUpdaterState field0;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdaterActivity_CheckFailedCopyWith<BridgeUpdaterActivity_CheckFailed> get copyWith => _$BridgeUpdaterActivity_CheckFailedCopyWithImpl<BridgeUpdaterActivity_CheckFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity_CheckFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeUpdaterActivity.checkFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdaterActivity_CheckFailedCopyWith<$Res> implements $BridgeUpdaterActivityCopyWith<$Res> {
  factory $BridgeUpdaterActivity_CheckFailedCopyWith(BridgeUpdaterActivity_CheckFailed value, $Res Function(BridgeUpdaterActivity_CheckFailed) _then) = _$BridgeUpdaterActivity_CheckFailedCopyWithImpl;
@useResult
$Res call({
 BridgeCheckFailedUpdaterState field0
});




}
/// @nodoc
class _$BridgeUpdaterActivity_CheckFailedCopyWithImpl<$Res>
    implements $BridgeUpdaterActivity_CheckFailedCopyWith<$Res> {
  _$BridgeUpdaterActivity_CheckFailedCopyWithImpl(this._self, this._then);

  final BridgeUpdaterActivity_CheckFailed _self;
  final $Res Function(BridgeUpdaterActivity_CheckFailed) _then;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeUpdaterActivity_CheckFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeCheckFailedUpdaterState,
  ));
}


}

/// @nodoc


class BridgeUpdaterActivity_InstallFailed extends BridgeUpdaterActivity {
  const BridgeUpdaterActivity_InstallFailed(this.field0): super._();


@override final  BridgeInstallFailedUpdaterState field0;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdaterActivity_InstallFailedCopyWith<BridgeUpdaterActivity_InstallFailed> get copyWith => _$BridgeUpdaterActivity_InstallFailedCopyWithImpl<BridgeUpdaterActivity_InstallFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdaterActivity_InstallFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeUpdaterActivity.installFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdaterActivity_InstallFailedCopyWith<$Res> implements $BridgeUpdaterActivityCopyWith<$Res> {
  factory $BridgeUpdaterActivity_InstallFailedCopyWith(BridgeUpdaterActivity_InstallFailed value, $Res Function(BridgeUpdaterActivity_InstallFailed) _then) = _$BridgeUpdaterActivity_InstallFailedCopyWithImpl;
@useResult
$Res call({
 BridgeInstallFailedUpdaterState field0
});




}
/// @nodoc
class _$BridgeUpdaterActivity_InstallFailedCopyWithImpl<$Res>
    implements $BridgeUpdaterActivity_InstallFailedCopyWith<$Res> {
  _$BridgeUpdaterActivity_InstallFailedCopyWithImpl(this._self, this._then);

  final BridgeUpdaterActivity_InstallFailed _self;
  final $Res Function(BridgeUpdaterActivity_InstallFailed) _then;

/// Create a copy of BridgeUpdaterActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeUpdaterActivity_InstallFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeInstallFailedUpdaterState,
  ));
}


}

// dart format on
