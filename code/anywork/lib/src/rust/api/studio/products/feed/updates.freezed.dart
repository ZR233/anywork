// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'updates.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeUpdatesBrief {

 BigInt get revision;
/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBriefCopyWith<BridgeUpdatesBrief> get copyWith => _$BridgeUpdatesBriefCopyWithImpl<BridgeUpdatesBrief>(this as BridgeUpdatesBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeUpdatesBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as BridgeUpdatesBrief;
  return Object.hash(runtimeType,_this.revision);
}

@override
String toString() {
  final _this = this as BridgeUpdatesBrief;
  return 'BridgeUpdatesBrief(revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBriefCopyWith<$Res>  {
  factory $BridgeUpdatesBriefCopyWith(BridgeUpdatesBrief value, $Res Function(BridgeUpdatesBrief) _then) = _$BridgeUpdatesBriefCopyWithImpl;
@useResult
$Res call({
 BigInt revision
});




}
/// @nodoc
class _$BridgeUpdatesBriefCopyWithImpl<$Res>
    implements $BridgeUpdatesBriefCopyWith<$Res> {
  _$BridgeUpdatesBriefCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief _self;
  final $Res Function(BridgeUpdatesBrief) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,}) {
  return _then(_self.copyWith(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeUpdatesBrief].
extension BridgeUpdatesBriefPatterns on BridgeUpdatesBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeUpdatesBrief_Disabled value)?  disabled,TResult Function( BridgeUpdatesBrief_Idle value)?  idle,TResult Function( BridgeUpdatesBrief_Checking value)?  checking,TResult Function( BridgeUpdatesBrief_UpToDate value)?  upToDate,TResult Function( BridgeUpdatesBrief_Available value)?  available,TResult Function( BridgeUpdatesBrief_Downloading value)?  downloading,TResult Function( BridgeUpdatesBrief_Verifying value)?  verifying,TResult Function( BridgeUpdatesBrief_Ready value)?  ready,TResult Function( BridgeUpdatesBrief_InstallerLaunched value)?  installerLaunched,TResult Function( BridgeUpdatesBrief_CheckFailed value)?  checkFailed,TResult Function( BridgeUpdatesBrief_InstallFailed value)?  installFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeUpdatesBrief_Disabled() when disabled != null:
return disabled(_that);case BridgeUpdatesBrief_Idle() when idle != null:
return idle(_that);case BridgeUpdatesBrief_Checking() when checking != null:
return checking(_that);case BridgeUpdatesBrief_UpToDate() when upToDate != null:
return upToDate(_that);case BridgeUpdatesBrief_Available() when available != null:
return available(_that);case BridgeUpdatesBrief_Downloading() when downloading != null:
return downloading(_that);case BridgeUpdatesBrief_Verifying() when verifying != null:
return verifying(_that);case BridgeUpdatesBrief_Ready() when ready != null:
return ready(_that);case BridgeUpdatesBrief_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that);case BridgeUpdatesBrief_CheckFailed() when checkFailed != null:
return checkFailed(_that);case BridgeUpdatesBrief_InstallFailed() when installFailed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeUpdatesBrief_Disabled value)  disabled,required TResult Function( BridgeUpdatesBrief_Idle value)  idle,required TResult Function( BridgeUpdatesBrief_Checking value)  checking,required TResult Function( BridgeUpdatesBrief_UpToDate value)  upToDate,required TResult Function( BridgeUpdatesBrief_Available value)  available,required TResult Function( BridgeUpdatesBrief_Downloading value)  downloading,required TResult Function( BridgeUpdatesBrief_Verifying value)  verifying,required TResult Function( BridgeUpdatesBrief_Ready value)  ready,required TResult Function( BridgeUpdatesBrief_InstallerLaunched value)  installerLaunched,required TResult Function( BridgeUpdatesBrief_CheckFailed value)  checkFailed,required TResult Function( BridgeUpdatesBrief_InstallFailed value)  installFailed,}){
final _that = this;
switch (_that) {
case BridgeUpdatesBrief_Disabled():
return disabled(_that);case BridgeUpdatesBrief_Idle():
return idle(_that);case BridgeUpdatesBrief_Checking():
return checking(_that);case BridgeUpdatesBrief_UpToDate():
return upToDate(_that);case BridgeUpdatesBrief_Available():
return available(_that);case BridgeUpdatesBrief_Downloading():
return downloading(_that);case BridgeUpdatesBrief_Verifying():
return verifying(_that);case BridgeUpdatesBrief_Ready():
return ready(_that);case BridgeUpdatesBrief_InstallerLaunched():
return installerLaunched(_that);case BridgeUpdatesBrief_CheckFailed():
return checkFailed(_that);case BridgeUpdatesBrief_InstallFailed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeUpdatesBrief_Disabled value)?  disabled,TResult? Function( BridgeUpdatesBrief_Idle value)?  idle,TResult? Function( BridgeUpdatesBrief_Checking value)?  checking,TResult? Function( BridgeUpdatesBrief_UpToDate value)?  upToDate,TResult? Function( BridgeUpdatesBrief_Available value)?  available,TResult? Function( BridgeUpdatesBrief_Downloading value)?  downloading,TResult? Function( BridgeUpdatesBrief_Verifying value)?  verifying,TResult? Function( BridgeUpdatesBrief_Ready value)?  ready,TResult? Function( BridgeUpdatesBrief_InstallerLaunched value)?  installerLaunched,TResult? Function( BridgeUpdatesBrief_CheckFailed value)?  checkFailed,TResult? Function( BridgeUpdatesBrief_InstallFailed value)?  installFailed,}){
final _that = this;
switch (_that) {
case BridgeUpdatesBrief_Disabled() when disabled != null:
return disabled(_that);case BridgeUpdatesBrief_Idle() when idle != null:
return idle(_that);case BridgeUpdatesBrief_Checking() when checking != null:
return checking(_that);case BridgeUpdatesBrief_UpToDate() when upToDate != null:
return upToDate(_that);case BridgeUpdatesBrief_Available() when available != null:
return available(_that);case BridgeUpdatesBrief_Downloading() when downloading != null:
return downloading(_that);case BridgeUpdatesBrief_Verifying() when verifying != null:
return verifying(_that);case BridgeUpdatesBrief_Ready() when ready != null:
return ready(_that);case BridgeUpdatesBrief_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that);case BridgeUpdatesBrief_CheckFailed() when checkFailed != null:
return checkFailed(_that);case BridgeUpdatesBrief_InstallFailed() when installFailed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt revision,  PlatformInt64 updatedAt)?  disabled,TResult Function( BigInt revision,  PlatformInt64 updatedAt)?  idle,TResult Function( BigInt revision,  PlatformInt64 startedAt)?  checking,TResult Function( BigInt revision,  PlatformInt64 checkedAt)?  upToDate,TResult Function( BigInt revision,  PlatformInt64 checkedAt)?  available,TResult Function( BigInt revision,  PlatformInt64 updatedAt,  BigInt downloaded,  BigInt total)?  downloading,TResult Function( BigInt revision,  PlatformInt64 updatedAt,  BigInt downloaded,  BigInt total)?  verifying,TResult Function( BigInt revision,  PlatformInt64 readyAt)?  ready,TResult Function( BigInt revision,  PlatformInt64 launchedAt)?  installerLaunched,TResult Function( BigInt revision,  PlatformInt64 failedAt,  bool retryable)?  checkFailed,TResult Function( BigInt revision,  PlatformInt64 failedAt,  bool retryable)?  installFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeUpdatesBrief_Disabled() when disabled != null:
return disabled(_that.revision,_that.updatedAt);case BridgeUpdatesBrief_Idle() when idle != null:
return idle(_that.revision,_that.updatedAt);case BridgeUpdatesBrief_Checking() when checking != null:
return checking(_that.revision,_that.startedAt);case BridgeUpdatesBrief_UpToDate() when upToDate != null:
return upToDate(_that.revision,_that.checkedAt);case BridgeUpdatesBrief_Available() when available != null:
return available(_that.revision,_that.checkedAt);case BridgeUpdatesBrief_Downloading() when downloading != null:
return downloading(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case BridgeUpdatesBrief_Verifying() when verifying != null:
return verifying(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case BridgeUpdatesBrief_Ready() when ready != null:
return ready(_that.revision,_that.readyAt);case BridgeUpdatesBrief_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that.revision,_that.launchedAt);case BridgeUpdatesBrief_CheckFailed() when checkFailed != null:
return checkFailed(_that.revision,_that.failedAt,_that.retryable);case BridgeUpdatesBrief_InstallFailed() when installFailed != null:
return installFailed(_that.revision,_that.failedAt,_that.retryable);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt revision,  PlatformInt64 updatedAt)  disabled,required TResult Function( BigInt revision,  PlatformInt64 updatedAt)  idle,required TResult Function( BigInt revision,  PlatformInt64 startedAt)  checking,required TResult Function( BigInt revision,  PlatformInt64 checkedAt)  upToDate,required TResult Function( BigInt revision,  PlatformInt64 checkedAt)  available,required TResult Function( BigInt revision,  PlatformInt64 updatedAt,  BigInt downloaded,  BigInt total)  downloading,required TResult Function( BigInt revision,  PlatformInt64 updatedAt,  BigInt downloaded,  BigInt total)  verifying,required TResult Function( BigInt revision,  PlatformInt64 readyAt)  ready,required TResult Function( BigInt revision,  PlatformInt64 launchedAt)  installerLaunched,required TResult Function( BigInt revision,  PlatformInt64 failedAt,  bool retryable)  checkFailed,required TResult Function( BigInt revision,  PlatformInt64 failedAt,  bool retryable)  installFailed,}) {final _that = this;
switch (_that) {
case BridgeUpdatesBrief_Disabled():
return disabled(_that.revision,_that.updatedAt);case BridgeUpdatesBrief_Idle():
return idle(_that.revision,_that.updatedAt);case BridgeUpdatesBrief_Checking():
return checking(_that.revision,_that.startedAt);case BridgeUpdatesBrief_UpToDate():
return upToDate(_that.revision,_that.checkedAt);case BridgeUpdatesBrief_Available():
return available(_that.revision,_that.checkedAt);case BridgeUpdatesBrief_Downloading():
return downloading(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case BridgeUpdatesBrief_Verifying():
return verifying(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case BridgeUpdatesBrief_Ready():
return ready(_that.revision,_that.readyAt);case BridgeUpdatesBrief_InstallerLaunched():
return installerLaunched(_that.revision,_that.launchedAt);case BridgeUpdatesBrief_CheckFailed():
return checkFailed(_that.revision,_that.failedAt,_that.retryable);case BridgeUpdatesBrief_InstallFailed():
return installFailed(_that.revision,_that.failedAt,_that.retryable);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt revision,  PlatformInt64 updatedAt)?  disabled,TResult? Function( BigInt revision,  PlatformInt64 updatedAt)?  idle,TResult? Function( BigInt revision,  PlatformInt64 startedAt)?  checking,TResult? Function( BigInt revision,  PlatformInt64 checkedAt)?  upToDate,TResult? Function( BigInt revision,  PlatformInt64 checkedAt)?  available,TResult? Function( BigInt revision,  PlatformInt64 updatedAt,  BigInt downloaded,  BigInt total)?  downloading,TResult? Function( BigInt revision,  PlatformInt64 updatedAt,  BigInt downloaded,  BigInt total)?  verifying,TResult? Function( BigInt revision,  PlatformInt64 readyAt)?  ready,TResult? Function( BigInt revision,  PlatformInt64 launchedAt)?  installerLaunched,TResult? Function( BigInt revision,  PlatformInt64 failedAt,  bool retryable)?  checkFailed,TResult? Function( BigInt revision,  PlatformInt64 failedAt,  bool retryable)?  installFailed,}) {final _that = this;
switch (_that) {
case BridgeUpdatesBrief_Disabled() when disabled != null:
return disabled(_that.revision,_that.updatedAt);case BridgeUpdatesBrief_Idle() when idle != null:
return idle(_that.revision,_that.updatedAt);case BridgeUpdatesBrief_Checking() when checking != null:
return checking(_that.revision,_that.startedAt);case BridgeUpdatesBrief_UpToDate() when upToDate != null:
return upToDate(_that.revision,_that.checkedAt);case BridgeUpdatesBrief_Available() when available != null:
return available(_that.revision,_that.checkedAt);case BridgeUpdatesBrief_Downloading() when downloading != null:
return downloading(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case BridgeUpdatesBrief_Verifying() when verifying != null:
return verifying(_that.revision,_that.updatedAt,_that.downloaded,_that.total);case BridgeUpdatesBrief_Ready() when ready != null:
return ready(_that.revision,_that.readyAt);case BridgeUpdatesBrief_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that.revision,_that.launchedAt);case BridgeUpdatesBrief_CheckFailed() when checkFailed != null:
return checkFailed(_that.revision,_that.failedAt,_that.retryable);case BridgeUpdatesBrief_InstallFailed() when installFailed != null:
return installFailed(_that.revision,_that.failedAt,_that.retryable);case _:
  return null;

}
}

}

/// @nodoc


class BridgeUpdatesBrief_Disabled extends BridgeUpdatesBrief {
  const BridgeUpdatesBrief_Disabled({required this.revision, required this.updatedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBrief_DisabledCopyWith<BridgeUpdatesBrief_Disabled> get copyWith => _$BridgeUpdatesBrief_DisabledCopyWithImpl<BridgeUpdatesBrief_Disabled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief_Disabled&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}

@override
String toString() {
    return 'BridgeUpdatesBrief.disabled(revision: $revision, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBrief_DisabledCopyWith<$Res> implements $BridgeUpdatesBriefCopyWith<$Res> {
  factory $BridgeUpdatesBrief_DisabledCopyWith(BridgeUpdatesBrief_Disabled value, $Res Function(BridgeUpdatesBrief_Disabled) _then) = _$BridgeUpdatesBrief_DisabledCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt
});




}
/// @nodoc
class _$BridgeUpdatesBrief_DisabledCopyWithImpl<$Res>
    implements $BridgeUpdatesBrief_DisabledCopyWith<$Res> {
  _$BridgeUpdatesBrief_DisabledCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief_Disabled _self;
  final $Res Function(BridgeUpdatesBrief_Disabled) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(BridgeUpdatesBrief_Disabled(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeUpdatesBrief_Idle extends BridgeUpdatesBrief {
  const BridgeUpdatesBrief_Idle({required this.revision, required this.updatedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBrief_IdleCopyWith<BridgeUpdatesBrief_Idle> get copyWith => _$BridgeUpdatesBrief_IdleCopyWithImpl<BridgeUpdatesBrief_Idle>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief_Idle&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}

@override
String toString() {
    return 'BridgeUpdatesBrief.idle(revision: $revision, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBrief_IdleCopyWith<$Res> implements $BridgeUpdatesBriefCopyWith<$Res> {
  factory $BridgeUpdatesBrief_IdleCopyWith(BridgeUpdatesBrief_Idle value, $Res Function(BridgeUpdatesBrief_Idle) _then) = _$BridgeUpdatesBrief_IdleCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt
});




}
/// @nodoc
class _$BridgeUpdatesBrief_IdleCopyWithImpl<$Res>
    implements $BridgeUpdatesBrief_IdleCopyWith<$Res> {
  _$BridgeUpdatesBrief_IdleCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief_Idle _self;
  final $Res Function(BridgeUpdatesBrief_Idle) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(BridgeUpdatesBrief_Idle(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeUpdatesBrief_Checking extends BridgeUpdatesBrief {
  const BridgeUpdatesBrief_Checking({required this.revision, required this.startedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 startedAt;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBrief_CheckingCopyWith<BridgeUpdatesBrief_Checking> get copyWith => _$BridgeUpdatesBrief_CheckingCopyWithImpl<BridgeUpdatesBrief_Checking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief_Checking&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,startedAt);
}

@override
String toString() {
    return 'BridgeUpdatesBrief.checking(revision: $revision, startedAt: $startedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBrief_CheckingCopyWith<$Res> implements $BridgeUpdatesBriefCopyWith<$Res> {
  factory $BridgeUpdatesBrief_CheckingCopyWith(BridgeUpdatesBrief_Checking value, $Res Function(BridgeUpdatesBrief_Checking) _then) = _$BridgeUpdatesBrief_CheckingCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 startedAt
});




}
/// @nodoc
class _$BridgeUpdatesBrief_CheckingCopyWithImpl<$Res>
    implements $BridgeUpdatesBrief_CheckingCopyWith<$Res> {
  _$BridgeUpdatesBrief_CheckingCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief_Checking _self;
  final $Res Function(BridgeUpdatesBrief_Checking) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? startedAt = null,}) {
  return _then(BridgeUpdatesBrief_Checking(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeUpdatesBrief_UpToDate extends BridgeUpdatesBrief {
  const BridgeUpdatesBrief_UpToDate({required this.revision, required this.checkedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 checkedAt;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBrief_UpToDateCopyWith<BridgeUpdatesBrief_UpToDate> get copyWith => _$BridgeUpdatesBrief_UpToDateCopyWithImpl<BridgeUpdatesBrief_UpToDate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief_UpToDate&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,checkedAt);
}

@override
String toString() {
    return 'BridgeUpdatesBrief.upToDate(revision: $revision, checkedAt: $checkedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBrief_UpToDateCopyWith<$Res> implements $BridgeUpdatesBriefCopyWith<$Res> {
  factory $BridgeUpdatesBrief_UpToDateCopyWith(BridgeUpdatesBrief_UpToDate value, $Res Function(BridgeUpdatesBrief_UpToDate) _then) = _$BridgeUpdatesBrief_UpToDateCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 checkedAt
});




}
/// @nodoc
class _$BridgeUpdatesBrief_UpToDateCopyWithImpl<$Res>
    implements $BridgeUpdatesBrief_UpToDateCopyWith<$Res> {
  _$BridgeUpdatesBrief_UpToDateCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief_UpToDate _self;
  final $Res Function(BridgeUpdatesBrief_UpToDate) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? checkedAt = null,}) {
  return _then(BridgeUpdatesBrief_UpToDate(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeUpdatesBrief_Available extends BridgeUpdatesBrief {
  const BridgeUpdatesBrief_Available({required this.revision, required this.checkedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 checkedAt;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBrief_AvailableCopyWith<BridgeUpdatesBrief_Available> get copyWith => _$BridgeUpdatesBrief_AvailableCopyWithImpl<BridgeUpdatesBrief_Available>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief_Available&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,checkedAt);
}

@override
String toString() {
    return 'BridgeUpdatesBrief.available(revision: $revision, checkedAt: $checkedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBrief_AvailableCopyWith<$Res> implements $BridgeUpdatesBriefCopyWith<$Res> {
  factory $BridgeUpdatesBrief_AvailableCopyWith(BridgeUpdatesBrief_Available value, $Res Function(BridgeUpdatesBrief_Available) _then) = _$BridgeUpdatesBrief_AvailableCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 checkedAt
});




}
/// @nodoc
class _$BridgeUpdatesBrief_AvailableCopyWithImpl<$Res>
    implements $BridgeUpdatesBrief_AvailableCopyWith<$Res> {
  _$BridgeUpdatesBrief_AvailableCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief_Available _self;
  final $Res Function(BridgeUpdatesBrief_Available) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? checkedAt = null,}) {
  return _then(BridgeUpdatesBrief_Available(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeUpdatesBrief_Downloading extends BridgeUpdatesBrief {
  const BridgeUpdatesBrief_Downloading({required this.revision, required this.updatedAt, required this.downloaded, required this.total}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;
 final  BigInt downloaded;
 final  BigInt total;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBrief_DownloadingCopyWith<BridgeUpdatesBrief_Downloading> get copyWith => _$BridgeUpdatesBrief_DownloadingCopyWithImpl<BridgeUpdatesBrief_Downloading>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief_Downloading&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,downloaded,total);
}

@override
String toString() {
    return 'BridgeUpdatesBrief.downloading(revision: $revision, updatedAt: $updatedAt, downloaded: $downloaded, total: $total)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBrief_DownloadingCopyWith<$Res> implements $BridgeUpdatesBriefCopyWith<$Res> {
  factory $BridgeUpdatesBrief_DownloadingCopyWith(BridgeUpdatesBrief_Downloading value, $Res Function(BridgeUpdatesBrief_Downloading) _then) = _$BridgeUpdatesBrief_DownloadingCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt, BigInt downloaded, BigInt total
});




}
/// @nodoc
class _$BridgeUpdatesBrief_DownloadingCopyWithImpl<$Res>
    implements $BridgeUpdatesBrief_DownloadingCopyWith<$Res> {
  _$BridgeUpdatesBrief_DownloadingCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief_Downloading _self;
  final $Res Function(BridgeUpdatesBrief_Downloading) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? downloaded = null,Object? total = null,}) {
  return _then(BridgeUpdatesBrief_Downloading(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as BigInt,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeUpdatesBrief_Verifying extends BridgeUpdatesBrief {
  const BridgeUpdatesBrief_Verifying({required this.revision, required this.updatedAt, required this.downloaded, required this.total}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;
 final  BigInt downloaded;
 final  BigInt total;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBrief_VerifyingCopyWith<BridgeUpdatesBrief_Verifying> get copyWith => _$BridgeUpdatesBrief_VerifyingCopyWithImpl<BridgeUpdatesBrief_Verifying>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief_Verifying&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,downloaded,total);
}

@override
String toString() {
    return 'BridgeUpdatesBrief.verifying(revision: $revision, updatedAt: $updatedAt, downloaded: $downloaded, total: $total)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBrief_VerifyingCopyWith<$Res> implements $BridgeUpdatesBriefCopyWith<$Res> {
  factory $BridgeUpdatesBrief_VerifyingCopyWith(BridgeUpdatesBrief_Verifying value, $Res Function(BridgeUpdatesBrief_Verifying) _then) = _$BridgeUpdatesBrief_VerifyingCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt, BigInt downloaded, BigInt total
});




}
/// @nodoc
class _$BridgeUpdatesBrief_VerifyingCopyWithImpl<$Res>
    implements $BridgeUpdatesBrief_VerifyingCopyWith<$Res> {
  _$BridgeUpdatesBrief_VerifyingCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief_Verifying _self;
  final $Res Function(BridgeUpdatesBrief_Verifying) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? downloaded = null,Object? total = null,}) {
  return _then(BridgeUpdatesBrief_Verifying(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as BigInt,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeUpdatesBrief_Ready extends BridgeUpdatesBrief {
  const BridgeUpdatesBrief_Ready({required this.revision, required this.readyAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 readyAt;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBrief_ReadyCopyWith<BridgeUpdatesBrief_Ready> get copyWith => _$BridgeUpdatesBrief_ReadyCopyWithImpl<BridgeUpdatesBrief_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief_Ready&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.readyAt, readyAt) || other.readyAt == readyAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,readyAt);
}

@override
String toString() {
    return 'BridgeUpdatesBrief.ready(revision: $revision, readyAt: $readyAt)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBrief_ReadyCopyWith<$Res> implements $BridgeUpdatesBriefCopyWith<$Res> {
  factory $BridgeUpdatesBrief_ReadyCopyWith(BridgeUpdatesBrief_Ready value, $Res Function(BridgeUpdatesBrief_Ready) _then) = _$BridgeUpdatesBrief_ReadyCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 readyAt
});




}
/// @nodoc
class _$BridgeUpdatesBrief_ReadyCopyWithImpl<$Res>
    implements $BridgeUpdatesBrief_ReadyCopyWith<$Res> {
  _$BridgeUpdatesBrief_ReadyCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief_Ready _self;
  final $Res Function(BridgeUpdatesBrief_Ready) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? readyAt = null,}) {
  return _then(BridgeUpdatesBrief_Ready(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,readyAt: null == readyAt ? _self.readyAt : readyAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeUpdatesBrief_InstallerLaunched extends BridgeUpdatesBrief {
  const BridgeUpdatesBrief_InstallerLaunched({required this.revision, required this.launchedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 launchedAt;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBrief_InstallerLaunchedCopyWith<BridgeUpdatesBrief_InstallerLaunched> get copyWith => _$BridgeUpdatesBrief_InstallerLaunchedCopyWithImpl<BridgeUpdatesBrief_InstallerLaunched>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief_InstallerLaunched&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.launchedAt, launchedAt) || other.launchedAt == launchedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,launchedAt);
}

@override
String toString() {
    return 'BridgeUpdatesBrief.installerLaunched(revision: $revision, launchedAt: $launchedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBrief_InstallerLaunchedCopyWith<$Res> implements $BridgeUpdatesBriefCopyWith<$Res> {
  factory $BridgeUpdatesBrief_InstallerLaunchedCopyWith(BridgeUpdatesBrief_InstallerLaunched value, $Res Function(BridgeUpdatesBrief_InstallerLaunched) _then) = _$BridgeUpdatesBrief_InstallerLaunchedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 launchedAt
});




}
/// @nodoc
class _$BridgeUpdatesBrief_InstallerLaunchedCopyWithImpl<$Res>
    implements $BridgeUpdatesBrief_InstallerLaunchedCopyWith<$Res> {
  _$BridgeUpdatesBrief_InstallerLaunchedCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief_InstallerLaunched _self;
  final $Res Function(BridgeUpdatesBrief_InstallerLaunched) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? launchedAt = null,}) {
  return _then(BridgeUpdatesBrief_InstallerLaunched(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,launchedAt: null == launchedAt ? _self.launchedAt : launchedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeUpdatesBrief_CheckFailed extends BridgeUpdatesBrief {
  const BridgeUpdatesBrief_CheckFailed({required this.revision, required this.failedAt, required this.retryable}): super._();


@override final  BigInt revision;
 final  PlatformInt64 failedAt;
 final  bool retryable;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBrief_CheckFailedCopyWith<BridgeUpdatesBrief_CheckFailed> get copyWith => _$BridgeUpdatesBrief_CheckFailedCopyWithImpl<BridgeUpdatesBrief_CheckFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief_CheckFailed&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,retryable);
}

@override
String toString() {
    return 'BridgeUpdatesBrief.checkFailed(revision: $revision, failedAt: $failedAt, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBrief_CheckFailedCopyWith<$Res> implements $BridgeUpdatesBriefCopyWith<$Res> {
  factory $BridgeUpdatesBrief_CheckFailedCopyWith(BridgeUpdatesBrief_CheckFailed value, $Res Function(BridgeUpdatesBrief_CheckFailed) _then) = _$BridgeUpdatesBrief_CheckFailedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 failedAt, bool retryable
});




}
/// @nodoc
class _$BridgeUpdatesBrief_CheckFailedCopyWithImpl<$Res>
    implements $BridgeUpdatesBrief_CheckFailedCopyWith<$Res> {
  _$BridgeUpdatesBrief_CheckFailedCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief_CheckFailed _self;
  final $Res Function(BridgeUpdatesBrief_CheckFailed) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? retryable = null,}) {
  return _then(BridgeUpdatesBrief_CheckFailed(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgeUpdatesBrief_InstallFailed extends BridgeUpdatesBrief {
  const BridgeUpdatesBrief_InstallFailed({required this.revision, required this.failedAt, required this.retryable}): super._();


@override final  BigInt revision;
 final  PlatformInt64 failedAt;
 final  bool retryable;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesBrief_InstallFailedCopyWith<BridgeUpdatesBrief_InstallFailed> get copyWith => _$BridgeUpdatesBrief_InstallFailedCopyWithImpl<BridgeUpdatesBrief_InstallFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesBrief_InstallFailed&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,retryable);
}

@override
String toString() {
    return 'BridgeUpdatesBrief.installFailed(revision: $revision, failedAt: $failedAt, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesBrief_InstallFailedCopyWith<$Res> implements $BridgeUpdatesBriefCopyWith<$Res> {
  factory $BridgeUpdatesBrief_InstallFailedCopyWith(BridgeUpdatesBrief_InstallFailed value, $Res Function(BridgeUpdatesBrief_InstallFailed) _then) = _$BridgeUpdatesBrief_InstallFailedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 failedAt, bool retryable
});




}
/// @nodoc
class _$BridgeUpdatesBrief_InstallFailedCopyWithImpl<$Res>
    implements $BridgeUpdatesBrief_InstallFailedCopyWith<$Res> {
  _$BridgeUpdatesBrief_InstallFailedCopyWithImpl(this._self, this._then);

  final BridgeUpdatesBrief_InstallFailed _self;
  final $Res Function(BridgeUpdatesBrief_InstallFailed) _then;

/// Create a copy of BridgeUpdatesBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? retryable = null,}) {
  return _then(BridgeUpdatesBrief_InstallFailed(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$BridgeUpdatesEvent {

 BridgeProductProjectionStamp get stamp; BridgeUpdatesHeader get value;
/// Create a copy of BridgeUpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesEventCopyWith<BridgeUpdatesEvent> get copyWith => _$BridgeUpdatesEventCopyWithImpl<BridgeUpdatesEvent>(this as BridgeUpdatesEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeUpdatesEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeUpdatesEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}

@override
String toString() {
  final _this = this as BridgeUpdatesEvent;
  return 'BridgeUpdatesEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesEventCopyWith<$Res>  {
  factory $BridgeUpdatesEventCopyWith(BridgeUpdatesEvent value, $Res Function(BridgeUpdatesEvent) _then) = _$BridgeUpdatesEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp, BridgeUpdatesHeader value
});




}
/// @nodoc
class _$BridgeUpdatesEventCopyWithImpl<$Res>
    implements $BridgeUpdatesEventCopyWith<$Res> {
  _$BridgeUpdatesEventCopyWithImpl(this._self, this._then);

  final BridgeUpdatesEvent _self;
  final $Res Function(BridgeUpdatesEvent) _then;

/// Create a copy of BridgeUpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeUpdatesHeader,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeUpdatesEvent].
extension BridgeUpdatesEventPatterns on BridgeUpdatesEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeUpdatesEvent_Baseline value)?  baseline,TResult Function( BridgeUpdatesEvent_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeUpdatesEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeUpdatesEvent_Replace() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeUpdatesEvent_Baseline value)  baseline,required TResult Function( BridgeUpdatesEvent_Replace value)  replace,}){
final _that = this;
switch (_that) {
case BridgeUpdatesEvent_Baseline():
return baseline(_that);case BridgeUpdatesEvent_Replace():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeUpdatesEvent_Baseline value)?  baseline,TResult? Function( BridgeUpdatesEvent_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case BridgeUpdatesEvent_Baseline() when baseline != null:
return baseline(_that);case BridgeUpdatesEvent_Replace() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeUpdatesHeader value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeUpdatesHeader value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeUpdatesEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeUpdatesEvent_Replace() when replace != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeUpdatesHeader value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeUpdatesHeader value)  replace,}) {final _that = this;
switch (_that) {
case BridgeUpdatesEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgeUpdatesEvent_Replace():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgeUpdatesHeader value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgeUpdatesHeader value)?  replace,}) {final _that = this;
switch (_that) {
case BridgeUpdatesEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgeUpdatesEvent_Replace() when replace != null:
return replace(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeUpdatesEvent_Baseline extends BridgeUpdatesEvent {
  const BridgeUpdatesEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgeUpdatesHeader value;

/// Create a copy of BridgeUpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesEvent_BaselineCopyWith<BridgeUpdatesEvent_Baseline> get copyWith => _$BridgeUpdatesEvent_BaselineCopyWithImpl<BridgeUpdatesEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgeUpdatesEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesEvent_BaselineCopyWith<$Res> implements $BridgeUpdatesEventCopyWith<$Res> {
  factory $BridgeUpdatesEvent_BaselineCopyWith(BridgeUpdatesEvent_Baseline value, $Res Function(BridgeUpdatesEvent_Baseline) _then) = _$BridgeUpdatesEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgeUpdatesHeader value
});




}
/// @nodoc
class _$BridgeUpdatesEvent_BaselineCopyWithImpl<$Res>
    implements $BridgeUpdatesEvent_BaselineCopyWith<$Res> {
  _$BridgeUpdatesEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgeUpdatesEvent_Baseline _self;
  final $Res Function(BridgeUpdatesEvent_Baseline) _then;

/// Create a copy of BridgeUpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgeUpdatesEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeUpdatesHeader,
  ));
}


}

/// @nodoc


class BridgeUpdatesEvent_Replace extends BridgeUpdatesEvent {
  const BridgeUpdatesEvent_Replace({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgeUpdatesHeader value;

/// Create a copy of BridgeUpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesEvent_ReplaceCopyWith<BridgeUpdatesEvent_Replace> get copyWith => _$BridgeUpdatesEvent_ReplaceCopyWithImpl<BridgeUpdatesEvent_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesEvent_Replace&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgeUpdatesEvent.replace(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesEvent_ReplaceCopyWith<$Res> implements $BridgeUpdatesEventCopyWith<$Res> {
  factory $BridgeUpdatesEvent_ReplaceCopyWith(BridgeUpdatesEvent_Replace value, $Res Function(BridgeUpdatesEvent_Replace) _then) = _$BridgeUpdatesEvent_ReplaceCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgeUpdatesHeader value
});




}
/// @nodoc
class _$BridgeUpdatesEvent_ReplaceCopyWithImpl<$Res>
    implements $BridgeUpdatesEvent_ReplaceCopyWith<$Res> {
  _$BridgeUpdatesEvent_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeUpdatesEvent_Replace _self;
  final $Res Function(BridgeUpdatesEvent_Replace) _then;

/// Create a copy of BridgeUpdatesEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgeUpdatesEvent_Replace(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeUpdatesHeader,
  ));
}


}

/// @nodoc
mixin _$BridgeUpdatesFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeUpdatesFrame()';
}


}

/// @nodoc
class $BridgeUpdatesFrameCopyWith<$Res>  {
$BridgeUpdatesFrameCopyWith(BridgeUpdatesFrame _, $Res Function(BridgeUpdatesFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeUpdatesFrame].
extension BridgeUpdatesFramePatterns on BridgeUpdatesFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeUpdatesFrame_Data value)?  data,TResult Function( BridgeUpdatesFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgeUpdatesFrame_Failure value)?  failure,TResult Function( BridgeUpdatesFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeUpdatesFrame_Data() when data != null:
return data(_that);case BridgeUpdatesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeUpdatesFrame_Failure() when failure != null:
return failure(_that);case BridgeUpdatesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeUpdatesFrame_Data value)  data,required TResult Function( BridgeUpdatesFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgeUpdatesFrame_Failure value)  failure,required TResult Function( BridgeUpdatesFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeUpdatesFrame_Data():
return data(_that);case BridgeUpdatesFrame_ResyncRequired():
return resyncRequired(_that);case BridgeUpdatesFrame_Failure():
return failure(_that);case BridgeUpdatesFrame_Closed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeUpdatesFrame_Data value)?  data,TResult? Function( BridgeUpdatesFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgeUpdatesFrame_Failure value)?  failure,TResult? Function( BridgeUpdatesFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeUpdatesFrame_Data() when data != null:
return data(_that);case BridgeUpdatesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgeUpdatesFrame_Failure() when failure != null:
return failure(_that);case BridgeUpdatesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgeUpdatesEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeUpdatesFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeUpdatesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeUpdatesFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeUpdatesFrame_Closed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgeUpdatesEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgeUpdatesFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgeUpdatesFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgeUpdatesFrame_Failure():
return failure(_that.identity,_that.error);case BridgeUpdatesFrame_Closed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgeUpdatesEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgeUpdatesFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgeUpdatesFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgeUpdatesFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgeUpdatesFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeUpdatesFrame_Data extends BridgeUpdatesFrame {
  const BridgeUpdatesFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgeUpdatesEvent event;

/// Create a copy of BridgeUpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesFrame_DataCopyWith<BridgeUpdatesFrame_Data> get copyWith => _$BridgeUpdatesFrame_DataCopyWithImpl<BridgeUpdatesFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgeUpdatesFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesFrame_DataCopyWith<$Res> implements $BridgeUpdatesFrameCopyWith<$Res> {
  factory $BridgeUpdatesFrame_DataCopyWith(BridgeUpdatesFrame_Data value, $Res Function(BridgeUpdatesFrame_Data) _then) = _$BridgeUpdatesFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgeUpdatesEvent event
});


$BridgeUpdatesEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeUpdatesFrame_DataCopyWithImpl<$Res>
    implements $BridgeUpdatesFrame_DataCopyWith<$Res> {
  _$BridgeUpdatesFrame_DataCopyWithImpl(this._self, this._then);

  final BridgeUpdatesFrame_Data _self;
  final $Res Function(BridgeUpdatesFrame_Data) _then;

/// Create a copy of BridgeUpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgeUpdatesFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeUpdatesEvent,
  ));
}

/// Create a copy of BridgeUpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeUpdatesEventCopyWith<$Res> get event {

  return $BridgeUpdatesEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgeUpdatesFrame_ResyncRequired extends BridgeUpdatesFrame {
  const BridgeUpdatesFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgeUpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesFrame_ResyncRequiredCopyWith<BridgeUpdatesFrame_ResyncRequired> get copyWith => _$BridgeUpdatesFrame_ResyncRequiredCopyWithImpl<BridgeUpdatesFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeUpdatesFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesFrame_ResyncRequiredCopyWith<$Res> implements $BridgeUpdatesFrameCopyWith<$Res> {
  factory $BridgeUpdatesFrame_ResyncRequiredCopyWith(BridgeUpdatesFrame_ResyncRequired value, $Res Function(BridgeUpdatesFrame_ResyncRequired) _then) = _$BridgeUpdatesFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgeUpdatesFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgeUpdatesFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgeUpdatesFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgeUpdatesFrame_ResyncRequired _self;
  final $Res Function(BridgeUpdatesFrame_ResyncRequired) _then;

/// Create a copy of BridgeUpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeUpdatesFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgeUpdatesFrame_Failure extends BridgeUpdatesFrame {
  const BridgeUpdatesFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgeUpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesFrame_FailureCopyWith<BridgeUpdatesFrame_Failure> get copyWith => _$BridgeUpdatesFrame_FailureCopyWithImpl<BridgeUpdatesFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgeUpdatesFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesFrame_FailureCopyWith<$Res> implements $BridgeUpdatesFrameCopyWith<$Res> {
  factory $BridgeUpdatesFrame_FailureCopyWith(BridgeUpdatesFrame_Failure value, $Res Function(BridgeUpdatesFrame_Failure) _then) = _$BridgeUpdatesFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgeUpdatesFrame_FailureCopyWithImpl<$Res>
    implements $BridgeUpdatesFrame_FailureCopyWith<$Res> {
  _$BridgeUpdatesFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgeUpdatesFrame_Failure _self;
  final $Res Function(BridgeUpdatesFrame_Failure) _then;

/// Create a copy of BridgeUpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgeUpdatesFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeUpdatesFrame_Closed extends BridgeUpdatesFrame {
  const BridgeUpdatesFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgeUpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesFrame_ClosedCopyWith<BridgeUpdatesFrame_Closed> get copyWith => _$BridgeUpdatesFrame_ClosedCopyWithImpl<BridgeUpdatesFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgeUpdatesFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesFrame_ClosedCopyWith<$Res> implements $BridgeUpdatesFrameCopyWith<$Res> {
  factory $BridgeUpdatesFrame_ClosedCopyWith(BridgeUpdatesFrame_Closed value, $Res Function(BridgeUpdatesFrame_Closed) _then) = _$BridgeUpdatesFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgeUpdatesFrame_ClosedCopyWithImpl<$Res>
    implements $BridgeUpdatesFrame_ClosedCopyWith<$Res> {
  _$BridgeUpdatesFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgeUpdatesFrame_Closed _self;
  final $Res Function(BridgeUpdatesFrame_Closed) _then;

/// Create a copy of BridgeUpdatesFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgeUpdatesFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
