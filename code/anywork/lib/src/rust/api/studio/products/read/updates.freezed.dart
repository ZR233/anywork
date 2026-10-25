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
mixin _$BridgeUpdatesReadHeader {

 BigInt get revision;
/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeaderCopyWith<BridgeUpdatesReadHeader> get copyWith => _$BridgeUpdatesReadHeaderCopyWithImpl<BridgeUpdatesReadHeader>(this as BridgeUpdatesReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeUpdatesReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as BridgeUpdatesReadHeader;
  return Object.hash(runtimeType,_this.revision);
}

@override
String toString() {
  final _this = this as BridgeUpdatesReadHeader;
  return 'BridgeUpdatesReadHeader(revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeaderCopyWith<$Res>  {
  factory $BridgeUpdatesReadHeaderCopyWith(BridgeUpdatesReadHeader value, $Res Function(BridgeUpdatesReadHeader) _then) = _$BridgeUpdatesReadHeaderCopyWithImpl;
@useResult
$Res call({
 BigInt revision
});




}
/// @nodoc
class _$BridgeUpdatesReadHeaderCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  _$BridgeUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader _self;
  final $Res Function(BridgeUpdatesReadHeader) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,}) {
  return _then(_self.copyWith(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeUpdatesReadHeader].
extension BridgeUpdatesReadHeaderPatterns on BridgeUpdatesReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeUpdatesReadHeader_Disabled value)?  disabled,TResult Function( BridgeUpdatesReadHeader_Idle value)?  idle,TResult Function( BridgeUpdatesReadHeader_Checking value)?  checking,TResult Function( BridgeUpdatesReadHeader_UpToDate value)?  upToDate,TResult Function( BridgeUpdatesReadHeader_Available value)?  available,TResult Function( BridgeUpdatesReadHeader_Downloading value)?  downloading,TResult Function( BridgeUpdatesReadHeader_Verifying value)?  verifying,TResult Function( BridgeUpdatesReadHeader_Ready value)?  ready,TResult Function( BridgeUpdatesReadHeader_InstallerLaunched value)?  installerLaunched,TResult Function( BridgeUpdatesReadHeader_CheckFailed value)?  checkFailed,TResult Function( BridgeUpdatesReadHeader_InstallFailed value)?  installFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeUpdatesReadHeader_Disabled() when disabled != null:
return disabled(_that);case BridgeUpdatesReadHeader_Idle() when idle != null:
return idle(_that);case BridgeUpdatesReadHeader_Checking() when checking != null:
return checking(_that);case BridgeUpdatesReadHeader_UpToDate() when upToDate != null:
return upToDate(_that);case BridgeUpdatesReadHeader_Available() when available != null:
return available(_that);case BridgeUpdatesReadHeader_Downloading() when downloading != null:
return downloading(_that);case BridgeUpdatesReadHeader_Verifying() when verifying != null:
return verifying(_that);case BridgeUpdatesReadHeader_Ready() when ready != null:
return ready(_that);case BridgeUpdatesReadHeader_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that);case BridgeUpdatesReadHeader_CheckFailed() when checkFailed != null:
return checkFailed(_that);case BridgeUpdatesReadHeader_InstallFailed() when installFailed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeUpdatesReadHeader_Disabled value)  disabled,required TResult Function( BridgeUpdatesReadHeader_Idle value)  idle,required TResult Function( BridgeUpdatesReadHeader_Checking value)  checking,required TResult Function( BridgeUpdatesReadHeader_UpToDate value)  upToDate,required TResult Function( BridgeUpdatesReadHeader_Available value)  available,required TResult Function( BridgeUpdatesReadHeader_Downloading value)  downloading,required TResult Function( BridgeUpdatesReadHeader_Verifying value)  verifying,required TResult Function( BridgeUpdatesReadHeader_Ready value)  ready,required TResult Function( BridgeUpdatesReadHeader_InstallerLaunched value)  installerLaunched,required TResult Function( BridgeUpdatesReadHeader_CheckFailed value)  checkFailed,required TResult Function( BridgeUpdatesReadHeader_InstallFailed value)  installFailed,}){
final _that = this;
switch (_that) {
case BridgeUpdatesReadHeader_Disabled():
return disabled(_that);case BridgeUpdatesReadHeader_Idle():
return idle(_that);case BridgeUpdatesReadHeader_Checking():
return checking(_that);case BridgeUpdatesReadHeader_UpToDate():
return upToDate(_that);case BridgeUpdatesReadHeader_Available():
return available(_that);case BridgeUpdatesReadHeader_Downloading():
return downloading(_that);case BridgeUpdatesReadHeader_Verifying():
return verifying(_that);case BridgeUpdatesReadHeader_Ready():
return ready(_that);case BridgeUpdatesReadHeader_InstallerLaunched():
return installerLaunched(_that);case BridgeUpdatesReadHeader_CheckFailed():
return checkFailed(_that);case BridgeUpdatesReadHeader_InstallFailed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeUpdatesReadHeader_Disabled value)?  disabled,TResult? Function( BridgeUpdatesReadHeader_Idle value)?  idle,TResult? Function( BridgeUpdatesReadHeader_Checking value)?  checking,TResult? Function( BridgeUpdatesReadHeader_UpToDate value)?  upToDate,TResult? Function( BridgeUpdatesReadHeader_Available value)?  available,TResult? Function( BridgeUpdatesReadHeader_Downloading value)?  downloading,TResult? Function( BridgeUpdatesReadHeader_Verifying value)?  verifying,TResult? Function( BridgeUpdatesReadHeader_Ready value)?  ready,TResult? Function( BridgeUpdatesReadHeader_InstallerLaunched value)?  installerLaunched,TResult? Function( BridgeUpdatesReadHeader_CheckFailed value)?  checkFailed,TResult? Function( BridgeUpdatesReadHeader_InstallFailed value)?  installFailed,}){
final _that = this;
switch (_that) {
case BridgeUpdatesReadHeader_Disabled() when disabled != null:
return disabled(_that);case BridgeUpdatesReadHeader_Idle() when idle != null:
return idle(_that);case BridgeUpdatesReadHeader_Checking() when checking != null:
return checking(_that);case BridgeUpdatesReadHeader_UpToDate() when upToDate != null:
return upToDate(_that);case BridgeUpdatesReadHeader_Available() when available != null:
return available(_that);case BridgeUpdatesReadHeader_Downloading() when downloading != null:
return downloading(_that);case BridgeUpdatesReadHeader_Verifying() when verifying != null:
return verifying(_that);case BridgeUpdatesReadHeader_Ready() when ready != null:
return ready(_that);case BridgeUpdatesReadHeader_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that);case BridgeUpdatesReadHeader_CheckFailed() when checkFailed != null:
return checkFailed(_that);case BridgeUpdatesReadHeader_InstallFailed() when installFailed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt revision,  PlatformInt64 updatedAt)?  disabled,TResult Function( BigInt revision,  PlatformInt64 updatedAt)?  idle,TResult Function( BigInt revision,  BridgeReadText operationId,  PlatformInt64 startedAt)?  checking,TResult Function( BigInt revision,  PlatformInt64 checkedAt)?  upToDate,TResult Function( BigInt revision,  PlatformInt64 checkedAt,  BridgeUpdateDetailsRead update)?  available,TResult Function( BigInt revision,  PlatformInt64 updatedAt,  BridgeUpdateDetailsRead update,  BigInt downloaded,  BigInt total)?  downloading,TResult Function( BigInt revision,  PlatformInt64 updatedAt,  BridgeUpdateDetailsRead update,  BigInt downloaded,  BigInt total)?  verifying,TResult Function( BigInt revision,  PlatformInt64 readyAt,  BridgeUpdateDetailsRead update)?  ready,TResult Function( BigInt revision,  PlatformInt64 launchedAt,  BridgeUpdateDetailsRead update)?  installerLaunched,TResult Function( BigInt revision,  PlatformInt64 failedAt,  BridgeSourceStateErrorRead error)?  checkFailed,TResult Function( BigInt revision,  PlatformInt64 failedAt,  BridgeUpdateDetailsRead update,  BridgeSourceStateErrorRead error)?  installFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeUpdatesReadHeader_Disabled() when disabled != null:
return disabled(_that.revision,_that.updatedAt);case BridgeUpdatesReadHeader_Idle() when idle != null:
return idle(_that.revision,_that.updatedAt);case BridgeUpdatesReadHeader_Checking() when checking != null:
return checking(_that.revision,_that.operationId,_that.startedAt);case BridgeUpdatesReadHeader_UpToDate() when upToDate != null:
return upToDate(_that.revision,_that.checkedAt);case BridgeUpdatesReadHeader_Available() when available != null:
return available(_that.revision,_that.checkedAt,_that.update);case BridgeUpdatesReadHeader_Downloading() when downloading != null:
return downloading(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case BridgeUpdatesReadHeader_Verifying() when verifying != null:
return verifying(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case BridgeUpdatesReadHeader_Ready() when ready != null:
return ready(_that.revision,_that.readyAt,_that.update);case BridgeUpdatesReadHeader_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that.revision,_that.launchedAt,_that.update);case BridgeUpdatesReadHeader_CheckFailed() when checkFailed != null:
return checkFailed(_that.revision,_that.failedAt,_that.error);case BridgeUpdatesReadHeader_InstallFailed() when installFailed != null:
return installFailed(_that.revision,_that.failedAt,_that.update,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt revision,  PlatformInt64 updatedAt)  disabled,required TResult Function( BigInt revision,  PlatformInt64 updatedAt)  idle,required TResult Function( BigInt revision,  BridgeReadText operationId,  PlatformInt64 startedAt)  checking,required TResult Function( BigInt revision,  PlatformInt64 checkedAt)  upToDate,required TResult Function( BigInt revision,  PlatformInt64 checkedAt,  BridgeUpdateDetailsRead update)  available,required TResult Function( BigInt revision,  PlatformInt64 updatedAt,  BridgeUpdateDetailsRead update,  BigInt downloaded,  BigInt total)  downloading,required TResult Function( BigInt revision,  PlatformInt64 updatedAt,  BridgeUpdateDetailsRead update,  BigInt downloaded,  BigInt total)  verifying,required TResult Function( BigInt revision,  PlatformInt64 readyAt,  BridgeUpdateDetailsRead update)  ready,required TResult Function( BigInt revision,  PlatformInt64 launchedAt,  BridgeUpdateDetailsRead update)  installerLaunched,required TResult Function( BigInt revision,  PlatformInt64 failedAt,  BridgeSourceStateErrorRead error)  checkFailed,required TResult Function( BigInt revision,  PlatformInt64 failedAt,  BridgeUpdateDetailsRead update,  BridgeSourceStateErrorRead error)  installFailed,}) {final _that = this;
switch (_that) {
case BridgeUpdatesReadHeader_Disabled():
return disabled(_that.revision,_that.updatedAt);case BridgeUpdatesReadHeader_Idle():
return idle(_that.revision,_that.updatedAt);case BridgeUpdatesReadHeader_Checking():
return checking(_that.revision,_that.operationId,_that.startedAt);case BridgeUpdatesReadHeader_UpToDate():
return upToDate(_that.revision,_that.checkedAt);case BridgeUpdatesReadHeader_Available():
return available(_that.revision,_that.checkedAt,_that.update);case BridgeUpdatesReadHeader_Downloading():
return downloading(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case BridgeUpdatesReadHeader_Verifying():
return verifying(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case BridgeUpdatesReadHeader_Ready():
return ready(_that.revision,_that.readyAt,_that.update);case BridgeUpdatesReadHeader_InstallerLaunched():
return installerLaunched(_that.revision,_that.launchedAt,_that.update);case BridgeUpdatesReadHeader_CheckFailed():
return checkFailed(_that.revision,_that.failedAt,_that.error);case BridgeUpdatesReadHeader_InstallFailed():
return installFailed(_that.revision,_that.failedAt,_that.update,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt revision,  PlatformInt64 updatedAt)?  disabled,TResult? Function( BigInt revision,  PlatformInt64 updatedAt)?  idle,TResult? Function( BigInt revision,  BridgeReadText operationId,  PlatformInt64 startedAt)?  checking,TResult? Function( BigInt revision,  PlatformInt64 checkedAt)?  upToDate,TResult? Function( BigInt revision,  PlatformInt64 checkedAt,  BridgeUpdateDetailsRead update)?  available,TResult? Function( BigInt revision,  PlatformInt64 updatedAt,  BridgeUpdateDetailsRead update,  BigInt downloaded,  BigInt total)?  downloading,TResult? Function( BigInt revision,  PlatformInt64 updatedAt,  BridgeUpdateDetailsRead update,  BigInt downloaded,  BigInt total)?  verifying,TResult? Function( BigInt revision,  PlatformInt64 readyAt,  BridgeUpdateDetailsRead update)?  ready,TResult? Function( BigInt revision,  PlatformInt64 launchedAt,  BridgeUpdateDetailsRead update)?  installerLaunched,TResult? Function( BigInt revision,  PlatformInt64 failedAt,  BridgeSourceStateErrorRead error)?  checkFailed,TResult? Function( BigInt revision,  PlatformInt64 failedAt,  BridgeUpdateDetailsRead update,  BridgeSourceStateErrorRead error)?  installFailed,}) {final _that = this;
switch (_that) {
case BridgeUpdatesReadHeader_Disabled() when disabled != null:
return disabled(_that.revision,_that.updatedAt);case BridgeUpdatesReadHeader_Idle() when idle != null:
return idle(_that.revision,_that.updatedAt);case BridgeUpdatesReadHeader_Checking() when checking != null:
return checking(_that.revision,_that.operationId,_that.startedAt);case BridgeUpdatesReadHeader_UpToDate() when upToDate != null:
return upToDate(_that.revision,_that.checkedAt);case BridgeUpdatesReadHeader_Available() when available != null:
return available(_that.revision,_that.checkedAt,_that.update);case BridgeUpdatesReadHeader_Downloading() when downloading != null:
return downloading(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case BridgeUpdatesReadHeader_Verifying() when verifying != null:
return verifying(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case BridgeUpdatesReadHeader_Ready() when ready != null:
return ready(_that.revision,_that.readyAt,_that.update);case BridgeUpdatesReadHeader_InstallerLaunched() when installerLaunched != null:
return installerLaunched(_that.revision,_that.launchedAt,_that.update);case BridgeUpdatesReadHeader_CheckFailed() when checkFailed != null:
return checkFailed(_that.revision,_that.failedAt,_that.error);case BridgeUpdatesReadHeader_InstallFailed() when installFailed != null:
return installFailed(_that.revision,_that.failedAt,_that.update,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeUpdatesReadHeader_Disabled extends BridgeUpdatesReadHeader {
  const BridgeUpdatesReadHeader_Disabled({required this.revision, required this.updatedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeader_DisabledCopyWith<BridgeUpdatesReadHeader_Disabled> get copyWith => _$BridgeUpdatesReadHeader_DisabledCopyWithImpl<BridgeUpdatesReadHeader_Disabled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader_Disabled&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}

@override
String toString() {
    return 'BridgeUpdatesReadHeader.disabled(revision: $revision, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeader_DisabledCopyWith<$Res> implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  factory $BridgeUpdatesReadHeader_DisabledCopyWith(BridgeUpdatesReadHeader_Disabled value, $Res Function(BridgeUpdatesReadHeader_Disabled) _then) = _$BridgeUpdatesReadHeader_DisabledCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt
});




}
/// @nodoc
class _$BridgeUpdatesReadHeader_DisabledCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeader_DisabledCopyWith<$Res> {
  _$BridgeUpdatesReadHeader_DisabledCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader_Disabled _self;
  final $Res Function(BridgeUpdatesReadHeader_Disabled) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(BridgeUpdatesReadHeader_Disabled(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeUpdatesReadHeader_Idle extends BridgeUpdatesReadHeader {
  const BridgeUpdatesReadHeader_Idle({required this.revision, required this.updatedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeader_IdleCopyWith<BridgeUpdatesReadHeader_Idle> get copyWith => _$BridgeUpdatesReadHeader_IdleCopyWithImpl<BridgeUpdatesReadHeader_Idle>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader_Idle&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}

@override
String toString() {
    return 'BridgeUpdatesReadHeader.idle(revision: $revision, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeader_IdleCopyWith<$Res> implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  factory $BridgeUpdatesReadHeader_IdleCopyWith(BridgeUpdatesReadHeader_Idle value, $Res Function(BridgeUpdatesReadHeader_Idle) _then) = _$BridgeUpdatesReadHeader_IdleCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt
});




}
/// @nodoc
class _$BridgeUpdatesReadHeader_IdleCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeader_IdleCopyWith<$Res> {
  _$BridgeUpdatesReadHeader_IdleCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader_Idle _self;
  final $Res Function(BridgeUpdatesReadHeader_Idle) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(BridgeUpdatesReadHeader_Idle(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeUpdatesReadHeader_Checking extends BridgeUpdatesReadHeader {
  const BridgeUpdatesReadHeader_Checking({required this.revision, required this.operationId, required this.startedAt}): super._();


@override final  BigInt revision;
 final  BridgeReadText operationId;
 final  PlatformInt64 startedAt;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeader_CheckingCopyWith<BridgeUpdatesReadHeader_Checking> get copyWith => _$BridgeUpdatesReadHeader_CheckingCopyWithImpl<BridgeUpdatesReadHeader_Checking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader_Checking&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,operationId,startedAt);
}

@override
String toString() {
    return 'BridgeUpdatesReadHeader.checking(revision: $revision, operationId: $operationId, startedAt: $startedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeader_CheckingCopyWith<$Res> implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  factory $BridgeUpdatesReadHeader_CheckingCopyWith(BridgeUpdatesReadHeader_Checking value, $Res Function(BridgeUpdatesReadHeader_Checking) _then) = _$BridgeUpdatesReadHeader_CheckingCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, BridgeReadText operationId, PlatformInt64 startedAt
});


$BridgeReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$BridgeUpdatesReadHeader_CheckingCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeader_CheckingCopyWith<$Res> {
  _$BridgeUpdatesReadHeader_CheckingCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader_Checking _self;
  final $Res Function(BridgeUpdatesReadHeader_Checking) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? operationId = null,Object? startedAt = null,}) {
  return _then(BridgeUpdatesReadHeader_Checking(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get operationId {

  return $BridgeReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc


class BridgeUpdatesReadHeader_UpToDate extends BridgeUpdatesReadHeader {
  const BridgeUpdatesReadHeader_UpToDate({required this.revision, required this.checkedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 checkedAt;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeader_UpToDateCopyWith<BridgeUpdatesReadHeader_UpToDate> get copyWith => _$BridgeUpdatesReadHeader_UpToDateCopyWithImpl<BridgeUpdatesReadHeader_UpToDate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader_UpToDate&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,checkedAt);
}

@override
String toString() {
    return 'BridgeUpdatesReadHeader.upToDate(revision: $revision, checkedAt: $checkedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeader_UpToDateCopyWith<$Res> implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  factory $BridgeUpdatesReadHeader_UpToDateCopyWith(BridgeUpdatesReadHeader_UpToDate value, $Res Function(BridgeUpdatesReadHeader_UpToDate) _then) = _$BridgeUpdatesReadHeader_UpToDateCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 checkedAt
});




}
/// @nodoc
class _$BridgeUpdatesReadHeader_UpToDateCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeader_UpToDateCopyWith<$Res> {
  _$BridgeUpdatesReadHeader_UpToDateCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader_UpToDate _self;
  final $Res Function(BridgeUpdatesReadHeader_UpToDate) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? checkedAt = null,}) {
  return _then(BridgeUpdatesReadHeader_UpToDate(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeUpdatesReadHeader_Available extends BridgeUpdatesReadHeader {
  const BridgeUpdatesReadHeader_Available({required this.revision, required this.checkedAt, required this.update}): super._();


@override final  BigInt revision;
 final  PlatformInt64 checkedAt;
 final  BridgeUpdateDetailsRead update;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeader_AvailableCopyWith<BridgeUpdatesReadHeader_Available> get copyWith => _$BridgeUpdatesReadHeader_AvailableCopyWithImpl<BridgeUpdatesReadHeader_Available>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader_Available&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,checkedAt,update);
}

@override
String toString() {
    return 'BridgeUpdatesReadHeader.available(revision: $revision, checkedAt: $checkedAt, update: $update)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeader_AvailableCopyWith<$Res> implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  factory $BridgeUpdatesReadHeader_AvailableCopyWith(BridgeUpdatesReadHeader_Available value, $Res Function(BridgeUpdatesReadHeader_Available) _then) = _$BridgeUpdatesReadHeader_AvailableCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 checkedAt, BridgeUpdateDetailsRead update
});




}
/// @nodoc
class _$BridgeUpdatesReadHeader_AvailableCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeader_AvailableCopyWith<$Res> {
  _$BridgeUpdatesReadHeader_AvailableCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader_Available _self;
  final $Res Function(BridgeUpdatesReadHeader_Available) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? checkedAt = null,Object? update = null,}) {
  return _then(BridgeUpdatesReadHeader_Available(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as BridgeUpdateDetailsRead,
  ));
}


}

/// @nodoc


class BridgeUpdatesReadHeader_Downloading extends BridgeUpdatesReadHeader {
  const BridgeUpdatesReadHeader_Downloading({required this.revision, required this.updatedAt, required this.update, required this.downloaded, required this.total}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;
 final  BridgeUpdateDetailsRead update;
 final  BigInt downloaded;
 final  BigInt total;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeader_DownloadingCopyWith<BridgeUpdatesReadHeader_Downloading> get copyWith => _$BridgeUpdatesReadHeader_DownloadingCopyWithImpl<BridgeUpdatesReadHeader_Downloading>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader_Downloading&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.update, update) || other.update == update)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,update,downloaded,total);
}

@override
String toString() {
    return 'BridgeUpdatesReadHeader.downloading(revision: $revision, updatedAt: $updatedAt, update: $update, downloaded: $downloaded, total: $total)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeader_DownloadingCopyWith<$Res> implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  factory $BridgeUpdatesReadHeader_DownloadingCopyWith(BridgeUpdatesReadHeader_Downloading value, $Res Function(BridgeUpdatesReadHeader_Downloading) _then) = _$BridgeUpdatesReadHeader_DownloadingCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt, BridgeUpdateDetailsRead update, BigInt downloaded, BigInt total
});




}
/// @nodoc
class _$BridgeUpdatesReadHeader_DownloadingCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeader_DownloadingCopyWith<$Res> {
  _$BridgeUpdatesReadHeader_DownloadingCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader_Downloading _self;
  final $Res Function(BridgeUpdatesReadHeader_Downloading) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? update = null,Object? downloaded = null,Object? total = null,}) {
  return _then(BridgeUpdatesReadHeader_Downloading(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as BridgeUpdateDetailsRead,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as BigInt,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeUpdatesReadHeader_Verifying extends BridgeUpdatesReadHeader {
  const BridgeUpdatesReadHeader_Verifying({required this.revision, required this.updatedAt, required this.update, required this.downloaded, required this.total}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;
 final  BridgeUpdateDetailsRead update;
 final  BigInt downloaded;
 final  BigInt total;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeader_VerifyingCopyWith<BridgeUpdatesReadHeader_Verifying> get copyWith => _$BridgeUpdatesReadHeader_VerifyingCopyWithImpl<BridgeUpdatesReadHeader_Verifying>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader_Verifying&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.update, update) || other.update == update)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,update,downloaded,total);
}

@override
String toString() {
    return 'BridgeUpdatesReadHeader.verifying(revision: $revision, updatedAt: $updatedAt, update: $update, downloaded: $downloaded, total: $total)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeader_VerifyingCopyWith<$Res> implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  factory $BridgeUpdatesReadHeader_VerifyingCopyWith(BridgeUpdatesReadHeader_Verifying value, $Res Function(BridgeUpdatesReadHeader_Verifying) _then) = _$BridgeUpdatesReadHeader_VerifyingCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt, BridgeUpdateDetailsRead update, BigInt downloaded, BigInt total
});




}
/// @nodoc
class _$BridgeUpdatesReadHeader_VerifyingCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeader_VerifyingCopyWith<$Res> {
  _$BridgeUpdatesReadHeader_VerifyingCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader_Verifying _self;
  final $Res Function(BridgeUpdatesReadHeader_Verifying) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? update = null,Object? downloaded = null,Object? total = null,}) {
  return _then(BridgeUpdatesReadHeader_Verifying(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as BridgeUpdateDetailsRead,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as BigInt,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeUpdatesReadHeader_Ready extends BridgeUpdatesReadHeader {
  const BridgeUpdatesReadHeader_Ready({required this.revision, required this.readyAt, required this.update}): super._();


@override final  BigInt revision;
 final  PlatformInt64 readyAt;
 final  BridgeUpdateDetailsRead update;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeader_ReadyCopyWith<BridgeUpdatesReadHeader_Ready> get copyWith => _$BridgeUpdatesReadHeader_ReadyCopyWithImpl<BridgeUpdatesReadHeader_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader_Ready&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.readyAt, readyAt) || other.readyAt == readyAt)&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,readyAt,update);
}

@override
String toString() {
    return 'BridgeUpdatesReadHeader.ready(revision: $revision, readyAt: $readyAt, update: $update)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeader_ReadyCopyWith<$Res> implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  factory $BridgeUpdatesReadHeader_ReadyCopyWith(BridgeUpdatesReadHeader_Ready value, $Res Function(BridgeUpdatesReadHeader_Ready) _then) = _$BridgeUpdatesReadHeader_ReadyCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 readyAt, BridgeUpdateDetailsRead update
});




}
/// @nodoc
class _$BridgeUpdatesReadHeader_ReadyCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeader_ReadyCopyWith<$Res> {
  _$BridgeUpdatesReadHeader_ReadyCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader_Ready _self;
  final $Res Function(BridgeUpdatesReadHeader_Ready) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? readyAt = null,Object? update = null,}) {
  return _then(BridgeUpdatesReadHeader_Ready(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,readyAt: null == readyAt ? _self.readyAt : readyAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as BridgeUpdateDetailsRead,
  ));
}


}

/// @nodoc


class BridgeUpdatesReadHeader_InstallerLaunched extends BridgeUpdatesReadHeader {
  const BridgeUpdatesReadHeader_InstallerLaunched({required this.revision, required this.launchedAt, required this.update}): super._();


@override final  BigInt revision;
 final  PlatformInt64 launchedAt;
 final  BridgeUpdateDetailsRead update;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeader_InstallerLaunchedCopyWith<BridgeUpdatesReadHeader_InstallerLaunched> get copyWith => _$BridgeUpdatesReadHeader_InstallerLaunchedCopyWithImpl<BridgeUpdatesReadHeader_InstallerLaunched>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader_InstallerLaunched&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.launchedAt, launchedAt) || other.launchedAt == launchedAt)&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,launchedAt,update);
}

@override
String toString() {
    return 'BridgeUpdatesReadHeader.installerLaunched(revision: $revision, launchedAt: $launchedAt, update: $update)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeader_InstallerLaunchedCopyWith<$Res> implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  factory $BridgeUpdatesReadHeader_InstallerLaunchedCopyWith(BridgeUpdatesReadHeader_InstallerLaunched value, $Res Function(BridgeUpdatesReadHeader_InstallerLaunched) _then) = _$BridgeUpdatesReadHeader_InstallerLaunchedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 launchedAt, BridgeUpdateDetailsRead update
});




}
/// @nodoc
class _$BridgeUpdatesReadHeader_InstallerLaunchedCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeader_InstallerLaunchedCopyWith<$Res> {
  _$BridgeUpdatesReadHeader_InstallerLaunchedCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader_InstallerLaunched _self;
  final $Res Function(BridgeUpdatesReadHeader_InstallerLaunched) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? launchedAt = null,Object? update = null,}) {
  return _then(BridgeUpdatesReadHeader_InstallerLaunched(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,launchedAt: null == launchedAt ? _self.launchedAt : launchedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as BridgeUpdateDetailsRead,
  ));
}


}

/// @nodoc


class BridgeUpdatesReadHeader_CheckFailed extends BridgeUpdatesReadHeader {
  const BridgeUpdatesReadHeader_CheckFailed({required this.revision, required this.failedAt, required this.error}): super._();


@override final  BigInt revision;
 final  PlatformInt64 failedAt;
 final  BridgeSourceStateErrorRead error;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeader_CheckFailedCopyWith<BridgeUpdatesReadHeader_CheckFailed> get copyWith => _$BridgeUpdatesReadHeader_CheckFailedCopyWithImpl<BridgeUpdatesReadHeader_CheckFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader_CheckFailed&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,error);
}

@override
String toString() {
    return 'BridgeUpdatesReadHeader.checkFailed(revision: $revision, failedAt: $failedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeader_CheckFailedCopyWith<$Res> implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  factory $BridgeUpdatesReadHeader_CheckFailedCopyWith(BridgeUpdatesReadHeader_CheckFailed value, $Res Function(BridgeUpdatesReadHeader_CheckFailed) _then) = _$BridgeUpdatesReadHeader_CheckFailedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 failedAt, BridgeSourceStateErrorRead error
});




}
/// @nodoc
class _$BridgeUpdatesReadHeader_CheckFailedCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeader_CheckFailedCopyWith<$Res> {
  _$BridgeUpdatesReadHeader_CheckFailedCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader_CheckFailed _self;
  final $Res Function(BridgeUpdatesReadHeader_CheckFailed) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? error = null,}) {
  return _then(BridgeUpdatesReadHeader_CheckFailed(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeSourceStateErrorRead,
  ));
}


}

/// @nodoc


class BridgeUpdatesReadHeader_InstallFailed extends BridgeUpdatesReadHeader {
  const BridgeUpdatesReadHeader_InstallFailed({required this.revision, required this.failedAt, required this.update, required this.error}): super._();


@override final  BigInt revision;
 final  PlatformInt64 failedAt;
 final  BridgeUpdateDetailsRead update;
 final  BridgeSourceStateErrorRead error;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeUpdatesReadHeader_InstallFailedCopyWith<BridgeUpdatesReadHeader_InstallFailed> get copyWith => _$BridgeUpdatesReadHeader_InstallFailedCopyWithImpl<BridgeUpdatesReadHeader_InstallFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeUpdatesReadHeader_InstallFailed&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.update, update) || other.update == update)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,update,error);
}

@override
String toString() {
    return 'BridgeUpdatesReadHeader.installFailed(revision: $revision, failedAt: $failedAt, update: $update, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeUpdatesReadHeader_InstallFailedCopyWith<$Res> implements $BridgeUpdatesReadHeaderCopyWith<$Res> {
  factory $BridgeUpdatesReadHeader_InstallFailedCopyWith(BridgeUpdatesReadHeader_InstallFailed value, $Res Function(BridgeUpdatesReadHeader_InstallFailed) _then) = _$BridgeUpdatesReadHeader_InstallFailedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 failedAt, BridgeUpdateDetailsRead update, BridgeSourceStateErrorRead error
});




}
/// @nodoc
class _$BridgeUpdatesReadHeader_InstallFailedCopyWithImpl<$Res>
    implements $BridgeUpdatesReadHeader_InstallFailedCopyWith<$Res> {
  _$BridgeUpdatesReadHeader_InstallFailedCopyWithImpl(this._self, this._then);

  final BridgeUpdatesReadHeader_InstallFailed _self;
  final $Res Function(BridgeUpdatesReadHeader_InstallFailed) _then;

/// Create a copy of BridgeUpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? update = null,Object? error = null,}) {
  return _then(BridgeUpdatesReadHeader_InstallFailed(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as BridgeUpdateDetailsRead,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeSourceStateErrorRead,
  ));
}


}

// dart format on
