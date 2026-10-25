// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'configuration_commands.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeConfigurationCommandOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationCommandOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeConfigurationCommandOutcome()';
}


}

/// @nodoc
class $BridgeConfigurationCommandOutcomeCopyWith<$Res>  {
$BridgeConfigurationCommandOutcomeCopyWith(BridgeConfigurationCommandOutcome _, $Res Function(BridgeConfigurationCommandOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeConfigurationCommandOutcome].
extension BridgeConfigurationCommandOutcomePatterns on BridgeConfigurationCommandOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeConfigurationCommandOutcome_Committed value)?  committed,TResult Function( BridgeConfigurationCommandOutcome_CommittedButUnobserved value)?  committedButUnobserved,TResult Function( BridgeConfigurationCommandOutcome_Rejected value)?  rejected,TResult Function( BridgeConfigurationCommandOutcome_Unknown value)?  unknown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeConfigurationCommandOutcome_Committed() when committed != null:
return committed(_that);case BridgeConfigurationCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that);case BridgeConfigurationCommandOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeConfigurationCommandOutcome_Unknown() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeConfigurationCommandOutcome_Committed value)  committed,required TResult Function( BridgeConfigurationCommandOutcome_CommittedButUnobserved value)  committedButUnobserved,required TResult Function( BridgeConfigurationCommandOutcome_Rejected value)  rejected,required TResult Function( BridgeConfigurationCommandOutcome_Unknown value)  unknown,}){
final _that = this;
switch (_that) {
case BridgeConfigurationCommandOutcome_Committed():
return committed(_that);case BridgeConfigurationCommandOutcome_CommittedButUnobserved():
return committedButUnobserved(_that);case BridgeConfigurationCommandOutcome_Rejected():
return rejected(_that);case BridgeConfigurationCommandOutcome_Unknown():
return unknown(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeConfigurationCommandOutcome_Committed value)?  committed,TResult? Function( BridgeConfigurationCommandOutcome_CommittedButUnobserved value)?  committedButUnobserved,TResult? Function( BridgeConfigurationCommandOutcome_Rejected value)?  rejected,TResult? Function( BridgeConfigurationCommandOutcome_Unknown value)?  unknown,}){
final _that = this;
switch (_that) {
case BridgeConfigurationCommandOutcome_Committed() when committed != null:
return committed(_that);case BridgeConfigurationCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that);case BridgeConfigurationCommandOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeConfigurationCommandOutcome_Unknown() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeConfigurationCommandReply reply)?  committed,TResult Function( BridgeStudioCommandReceipt receipt,  BridgeError error)?  committedButUnobserved,TResult Function( String operationId,  BridgeError error)?  rejected,TResult Function( String operationId,  BridgeError error)?  unknown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeConfigurationCommandOutcome_Committed() when committed != null:
return committed(_that.reply);case BridgeConfigurationCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that.receipt,_that.error);case BridgeConfigurationCommandOutcome_Rejected() when rejected != null:
return rejected(_that.operationId,_that.error);case BridgeConfigurationCommandOutcome_Unknown() when unknown != null:
return unknown(_that.operationId,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeConfigurationCommandReply reply)  committed,required TResult Function( BridgeStudioCommandReceipt receipt,  BridgeError error)  committedButUnobserved,required TResult Function( String operationId,  BridgeError error)  rejected,required TResult Function( String operationId,  BridgeError error)  unknown,}) {final _that = this;
switch (_that) {
case BridgeConfigurationCommandOutcome_Committed():
return committed(_that.reply);case BridgeConfigurationCommandOutcome_CommittedButUnobserved():
return committedButUnobserved(_that.receipt,_that.error);case BridgeConfigurationCommandOutcome_Rejected():
return rejected(_that.operationId,_that.error);case BridgeConfigurationCommandOutcome_Unknown():
return unknown(_that.operationId,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeConfigurationCommandReply reply)?  committed,TResult? Function( BridgeStudioCommandReceipt receipt,  BridgeError error)?  committedButUnobserved,TResult? Function( String operationId,  BridgeError error)?  rejected,TResult? Function( String operationId,  BridgeError error)?  unknown,}) {final _that = this;
switch (_that) {
case BridgeConfigurationCommandOutcome_Committed() when committed != null:
return committed(_that.reply);case BridgeConfigurationCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that.receipt,_that.error);case BridgeConfigurationCommandOutcome_Rejected() when rejected != null:
return rejected(_that.operationId,_that.error);case BridgeConfigurationCommandOutcome_Unknown() when unknown != null:
return unknown(_that.operationId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeConfigurationCommandOutcome_Committed extends BridgeConfigurationCommandOutcome {
  const BridgeConfigurationCommandOutcome_Committed({required this.reply}): super._();


 final  BridgeConfigurationCommandReply reply;

/// Create a copy of BridgeConfigurationCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationCommandOutcome_CommittedCopyWith<BridgeConfigurationCommandOutcome_Committed> get copyWith => _$BridgeConfigurationCommandOutcome_CommittedCopyWithImpl<BridgeConfigurationCommandOutcome_Committed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationCommandOutcome_Committed&&(identical(other.reply, reply) || other.reply == reply));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reply);
}

@override
String toString() {
    return 'BridgeConfigurationCommandOutcome.committed(reply: $reply)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationCommandOutcome_CommittedCopyWith<$Res> implements $BridgeConfigurationCommandOutcomeCopyWith<$Res> {
  factory $BridgeConfigurationCommandOutcome_CommittedCopyWith(BridgeConfigurationCommandOutcome_Committed value, $Res Function(BridgeConfigurationCommandOutcome_Committed) _then) = _$BridgeConfigurationCommandOutcome_CommittedCopyWithImpl;
@useResult
$Res call({
 BridgeConfigurationCommandReply reply
});




}
/// @nodoc
class _$BridgeConfigurationCommandOutcome_CommittedCopyWithImpl<$Res>
    implements $BridgeConfigurationCommandOutcome_CommittedCopyWith<$Res> {
  _$BridgeConfigurationCommandOutcome_CommittedCopyWithImpl(this._self, this._then);

  final BridgeConfigurationCommandOutcome_Committed _self;
  final $Res Function(BridgeConfigurationCommandOutcome_Committed) _then;

/// Create a copy of BridgeConfigurationCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reply = null,}) {
  return _then(BridgeConfigurationCommandOutcome_Committed(
reply: null == reply ? _self.reply : reply // ignore: cast_nullable_to_non_nullable
as BridgeConfigurationCommandReply,
  ));
}


}

/// @nodoc


class BridgeConfigurationCommandOutcome_CommittedButUnobserved extends BridgeConfigurationCommandOutcome {
  const BridgeConfigurationCommandOutcome_CommittedButUnobserved({required this.receipt, required this.error}): super._();


 final  BridgeStudioCommandReceipt receipt;
 final  BridgeError error;

/// Create a copy of BridgeConfigurationCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationCommandOutcome_CommittedButUnobservedCopyWith<BridgeConfigurationCommandOutcome_CommittedButUnobserved> get copyWith => _$BridgeConfigurationCommandOutcome_CommittedButUnobservedCopyWithImpl<BridgeConfigurationCommandOutcome_CommittedButUnobserved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationCommandOutcome_CommittedButUnobserved&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receipt,error);
}

@override
String toString() {
    return 'BridgeConfigurationCommandOutcome.committedButUnobserved(receipt: $receipt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationCommandOutcome_CommittedButUnobservedCopyWith<$Res> implements $BridgeConfigurationCommandOutcomeCopyWith<$Res> {
  factory $BridgeConfigurationCommandOutcome_CommittedButUnobservedCopyWith(BridgeConfigurationCommandOutcome_CommittedButUnobserved value, $Res Function(BridgeConfigurationCommandOutcome_CommittedButUnobserved) _then) = _$BridgeConfigurationCommandOutcome_CommittedButUnobservedCopyWithImpl;
@useResult
$Res call({
 BridgeStudioCommandReceipt receipt, BridgeError error
});




}
/// @nodoc
class _$BridgeConfigurationCommandOutcome_CommittedButUnobservedCopyWithImpl<$Res>
    implements $BridgeConfigurationCommandOutcome_CommittedButUnobservedCopyWith<$Res> {
  _$BridgeConfigurationCommandOutcome_CommittedButUnobservedCopyWithImpl(this._self, this._then);

  final BridgeConfigurationCommandOutcome_CommittedButUnobserved _self;
  final $Res Function(BridgeConfigurationCommandOutcome_CommittedButUnobserved) _then;

/// Create a copy of BridgeConfigurationCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? receipt = null,Object? error = null,}) {
  return _then(BridgeConfigurationCommandOutcome_CommittedButUnobserved(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as BridgeStudioCommandReceipt,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeConfigurationCommandOutcome_Rejected extends BridgeConfigurationCommandOutcome {
  const BridgeConfigurationCommandOutcome_Rejected({required this.operationId, required this.error}): super._();


 final  String operationId;
 final  BridgeError error;

/// Create a copy of BridgeConfigurationCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationCommandOutcome_RejectedCopyWith<BridgeConfigurationCommandOutcome_Rejected> get copyWith => _$BridgeConfigurationCommandOutcome_RejectedCopyWithImpl<BridgeConfigurationCommandOutcome_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationCommandOutcome_Rejected&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,error);
}

@override
String toString() {
    return 'BridgeConfigurationCommandOutcome.rejected(operationId: $operationId, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationCommandOutcome_RejectedCopyWith<$Res> implements $BridgeConfigurationCommandOutcomeCopyWith<$Res> {
  factory $BridgeConfigurationCommandOutcome_RejectedCopyWith(BridgeConfigurationCommandOutcome_Rejected value, $Res Function(BridgeConfigurationCommandOutcome_Rejected) _then) = _$BridgeConfigurationCommandOutcome_RejectedCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeError error
});




}
/// @nodoc
class _$BridgeConfigurationCommandOutcome_RejectedCopyWithImpl<$Res>
    implements $BridgeConfigurationCommandOutcome_RejectedCopyWith<$Res> {
  _$BridgeConfigurationCommandOutcome_RejectedCopyWithImpl(this._self, this._then);

  final BridgeConfigurationCommandOutcome_Rejected _self;
  final $Res Function(BridgeConfigurationCommandOutcome_Rejected) _then;

/// Create a copy of BridgeConfigurationCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? error = null,}) {
  return _then(BridgeConfigurationCommandOutcome_Rejected(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeConfigurationCommandOutcome_Unknown extends BridgeConfigurationCommandOutcome {
  const BridgeConfigurationCommandOutcome_Unknown({required this.operationId, required this.error}): super._();


 final  String operationId;
 final  BridgeError error;

/// Create a copy of BridgeConfigurationCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationCommandOutcome_UnknownCopyWith<BridgeConfigurationCommandOutcome_Unknown> get copyWith => _$BridgeConfigurationCommandOutcome_UnknownCopyWithImpl<BridgeConfigurationCommandOutcome_Unknown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationCommandOutcome_Unknown&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,error);
}

@override
String toString() {
    return 'BridgeConfigurationCommandOutcome.unknown(operationId: $operationId, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationCommandOutcome_UnknownCopyWith<$Res> implements $BridgeConfigurationCommandOutcomeCopyWith<$Res> {
  factory $BridgeConfigurationCommandOutcome_UnknownCopyWith(BridgeConfigurationCommandOutcome_Unknown value, $Res Function(BridgeConfigurationCommandOutcome_Unknown) _then) = _$BridgeConfigurationCommandOutcome_UnknownCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeError error
});




}
/// @nodoc
class _$BridgeConfigurationCommandOutcome_UnknownCopyWithImpl<$Res>
    implements $BridgeConfigurationCommandOutcome_UnknownCopyWith<$Res> {
  _$BridgeConfigurationCommandOutcome_UnknownCopyWithImpl(this._self, this._then);

  final BridgeConfigurationCommandOutcome_Unknown _self;
  final $Res Function(BridgeConfigurationCommandOutcome_Unknown) _then;

/// Create a copy of BridgeConfigurationCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? error = null,}) {
  return _then(BridgeConfigurationCommandOutcome_Unknown(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc
mixin _$BridgeConfigurationMutation {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationMutation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeConfigurationMutation()';
}


}

/// @nodoc
class $BridgeConfigurationMutationCopyWith<$Res>  {
$BridgeConfigurationMutationCopyWith(BridgeConfigurationMutation _, $Res Function(BridgeConfigurationMutation) __);
}


/// Adds pattern-matching-related methods to [BridgeConfigurationMutation].
extension BridgeConfigurationMutationPatterns on BridgeConfigurationMutation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeConfigurationMutation_SaveAccount value)?  saveAccount,TResult Function( BridgeConfigurationMutation_SetDefaultAccount value)?  setDefaultAccount,TResult Function( BridgeConfigurationMutation_RemoveAccount value)?  removeAccount,TResult Function( BridgeConfigurationMutation_RemoveAccountModel value)?  removeAccountModel,TResult Function( BridgeConfigurationMutation_SetAccountModelEnabled value)?  setAccountModelEnabled,TResult Function( BridgeConfigurationMutation_SetAccountBillingKind value)?  setAccountBillingKind,TResult Function( BridgeConfigurationMutation_ApplyField value)?  applyField,TResult Function( BridgeConfigurationMutation_SetPermission value)?  setPermission,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeConfigurationMutation_SaveAccount() when saveAccount != null:
return saveAccount(_that);case BridgeConfigurationMutation_SetDefaultAccount() when setDefaultAccount != null:
return setDefaultAccount(_that);case BridgeConfigurationMutation_RemoveAccount() when removeAccount != null:
return removeAccount(_that);case BridgeConfigurationMutation_RemoveAccountModel() when removeAccountModel != null:
return removeAccountModel(_that);case BridgeConfigurationMutation_SetAccountModelEnabled() when setAccountModelEnabled != null:
return setAccountModelEnabled(_that);case BridgeConfigurationMutation_SetAccountBillingKind() when setAccountBillingKind != null:
return setAccountBillingKind(_that);case BridgeConfigurationMutation_ApplyField() when applyField != null:
return applyField(_that);case BridgeConfigurationMutation_SetPermission() when setPermission != null:
return setPermission(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeConfigurationMutation_SaveAccount value)  saveAccount,required TResult Function( BridgeConfigurationMutation_SetDefaultAccount value)  setDefaultAccount,required TResult Function( BridgeConfigurationMutation_RemoveAccount value)  removeAccount,required TResult Function( BridgeConfigurationMutation_RemoveAccountModel value)  removeAccountModel,required TResult Function( BridgeConfigurationMutation_SetAccountModelEnabled value)  setAccountModelEnabled,required TResult Function( BridgeConfigurationMutation_SetAccountBillingKind value)  setAccountBillingKind,required TResult Function( BridgeConfigurationMutation_ApplyField value)  applyField,required TResult Function( BridgeConfigurationMutation_SetPermission value)  setPermission,}){
final _that = this;
switch (_that) {
case BridgeConfigurationMutation_SaveAccount():
return saveAccount(_that);case BridgeConfigurationMutation_SetDefaultAccount():
return setDefaultAccount(_that);case BridgeConfigurationMutation_RemoveAccount():
return removeAccount(_that);case BridgeConfigurationMutation_RemoveAccountModel():
return removeAccountModel(_that);case BridgeConfigurationMutation_SetAccountModelEnabled():
return setAccountModelEnabled(_that);case BridgeConfigurationMutation_SetAccountBillingKind():
return setAccountBillingKind(_that);case BridgeConfigurationMutation_ApplyField():
return applyField(_that);case BridgeConfigurationMutation_SetPermission():
return setPermission(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeConfigurationMutation_SaveAccount value)?  saveAccount,TResult? Function( BridgeConfigurationMutation_SetDefaultAccount value)?  setDefaultAccount,TResult? Function( BridgeConfigurationMutation_RemoveAccount value)?  removeAccount,TResult? Function( BridgeConfigurationMutation_RemoveAccountModel value)?  removeAccountModel,TResult? Function( BridgeConfigurationMutation_SetAccountModelEnabled value)?  setAccountModelEnabled,TResult? Function( BridgeConfigurationMutation_SetAccountBillingKind value)?  setAccountBillingKind,TResult? Function( BridgeConfigurationMutation_ApplyField value)?  applyField,TResult? Function( BridgeConfigurationMutation_SetPermission value)?  setPermission,}){
final _that = this;
switch (_that) {
case BridgeConfigurationMutation_SaveAccount() when saveAccount != null:
return saveAccount(_that);case BridgeConfigurationMutation_SetDefaultAccount() when setDefaultAccount != null:
return setDefaultAccount(_that);case BridgeConfigurationMutation_RemoveAccount() when removeAccount != null:
return removeAccount(_that);case BridgeConfigurationMutation_RemoveAccountModel() when removeAccountModel != null:
return removeAccountModel(_that);case BridgeConfigurationMutation_SetAccountModelEnabled() when setAccountModelEnabled != null:
return setAccountModelEnabled(_that);case BridgeConfigurationMutation_SetAccountBillingKind() when setAccountBillingKind != null:
return setAccountBillingKind(_that);case BridgeConfigurationMutation_ApplyField() when applyField != null:
return applyField(_that);case BridgeConfigurationMutation_SetPermission() when setPermission != null:
return setPermission(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( AccountSettingsInput input)?  saveAccount,TResult Function( String accountId)?  setDefaultAccount,TResult Function( String accountId,  String? replacementAccountId)?  removeAccount,TResult Function( String accountId,  String modelId)?  removeAccountModel,TResult Function( String accountId,  String modelId,  bool enabled)?  setAccountModelEnabled,TResult Function( String accountId,  BridgeBillingKind? billingKind)?  setAccountBillingKind,TResult Function( SettingsFieldInput update)?  applyField,TResult Function( String mode)?  setPermission,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeConfigurationMutation_SaveAccount() when saveAccount != null:
return saveAccount(_that.input);case BridgeConfigurationMutation_SetDefaultAccount() when setDefaultAccount != null:
return setDefaultAccount(_that.accountId);case BridgeConfigurationMutation_RemoveAccount() when removeAccount != null:
return removeAccount(_that.accountId,_that.replacementAccountId);case BridgeConfigurationMutation_RemoveAccountModel() when removeAccountModel != null:
return removeAccountModel(_that.accountId,_that.modelId);case BridgeConfigurationMutation_SetAccountModelEnabled() when setAccountModelEnabled != null:
return setAccountModelEnabled(_that.accountId,_that.modelId,_that.enabled);case BridgeConfigurationMutation_SetAccountBillingKind() when setAccountBillingKind != null:
return setAccountBillingKind(_that.accountId,_that.billingKind);case BridgeConfigurationMutation_ApplyField() when applyField != null:
return applyField(_that.update);case BridgeConfigurationMutation_SetPermission() when setPermission != null:
return setPermission(_that.mode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( AccountSettingsInput input)  saveAccount,required TResult Function( String accountId)  setDefaultAccount,required TResult Function( String accountId,  String? replacementAccountId)  removeAccount,required TResult Function( String accountId,  String modelId)  removeAccountModel,required TResult Function( String accountId,  String modelId,  bool enabled)  setAccountModelEnabled,required TResult Function( String accountId,  BridgeBillingKind? billingKind)  setAccountBillingKind,required TResult Function( SettingsFieldInput update)  applyField,required TResult Function( String mode)  setPermission,}) {final _that = this;
switch (_that) {
case BridgeConfigurationMutation_SaveAccount():
return saveAccount(_that.input);case BridgeConfigurationMutation_SetDefaultAccount():
return setDefaultAccount(_that.accountId);case BridgeConfigurationMutation_RemoveAccount():
return removeAccount(_that.accountId,_that.replacementAccountId);case BridgeConfigurationMutation_RemoveAccountModel():
return removeAccountModel(_that.accountId,_that.modelId);case BridgeConfigurationMutation_SetAccountModelEnabled():
return setAccountModelEnabled(_that.accountId,_that.modelId,_that.enabled);case BridgeConfigurationMutation_SetAccountBillingKind():
return setAccountBillingKind(_that.accountId,_that.billingKind);case BridgeConfigurationMutation_ApplyField():
return applyField(_that.update);case BridgeConfigurationMutation_SetPermission():
return setPermission(_that.mode);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( AccountSettingsInput input)?  saveAccount,TResult? Function( String accountId)?  setDefaultAccount,TResult? Function( String accountId,  String? replacementAccountId)?  removeAccount,TResult? Function( String accountId,  String modelId)?  removeAccountModel,TResult? Function( String accountId,  String modelId,  bool enabled)?  setAccountModelEnabled,TResult? Function( String accountId,  BridgeBillingKind? billingKind)?  setAccountBillingKind,TResult? Function( SettingsFieldInput update)?  applyField,TResult? Function( String mode)?  setPermission,}) {final _that = this;
switch (_that) {
case BridgeConfigurationMutation_SaveAccount() when saveAccount != null:
return saveAccount(_that.input);case BridgeConfigurationMutation_SetDefaultAccount() when setDefaultAccount != null:
return setDefaultAccount(_that.accountId);case BridgeConfigurationMutation_RemoveAccount() when removeAccount != null:
return removeAccount(_that.accountId,_that.replacementAccountId);case BridgeConfigurationMutation_RemoveAccountModel() when removeAccountModel != null:
return removeAccountModel(_that.accountId,_that.modelId);case BridgeConfigurationMutation_SetAccountModelEnabled() when setAccountModelEnabled != null:
return setAccountModelEnabled(_that.accountId,_that.modelId,_that.enabled);case BridgeConfigurationMutation_SetAccountBillingKind() when setAccountBillingKind != null:
return setAccountBillingKind(_that.accountId,_that.billingKind);case BridgeConfigurationMutation_ApplyField() when applyField != null:
return applyField(_that.update);case BridgeConfigurationMutation_SetPermission() when setPermission != null:
return setPermission(_that.mode);case _:
  return null;

}
}

}

/// @nodoc


class BridgeConfigurationMutation_SaveAccount extends BridgeConfigurationMutation {
  const BridgeConfigurationMutation_SaveAccount({required this.input}): super._();


 final  AccountSettingsInput input;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationMutation_SaveAccountCopyWith<BridgeConfigurationMutation_SaveAccount> get copyWith => _$BridgeConfigurationMutation_SaveAccountCopyWithImpl<BridgeConfigurationMutation_SaveAccount>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationMutation_SaveAccount&&(identical(other.input, input) || other.input == input));
}


@override
int get hashCode {
    return Object.hash(runtimeType,input);
}

@override
String toString() {
    return 'BridgeConfigurationMutation.saveAccount(input: $input)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationMutation_SaveAccountCopyWith<$Res> implements $BridgeConfigurationMutationCopyWith<$Res> {
  factory $BridgeConfigurationMutation_SaveAccountCopyWith(BridgeConfigurationMutation_SaveAccount value, $Res Function(BridgeConfigurationMutation_SaveAccount) _then) = _$BridgeConfigurationMutation_SaveAccountCopyWithImpl;
@useResult
$Res call({
 AccountSettingsInput input
});




}
/// @nodoc
class _$BridgeConfigurationMutation_SaveAccountCopyWithImpl<$Res>
    implements $BridgeConfigurationMutation_SaveAccountCopyWith<$Res> {
  _$BridgeConfigurationMutation_SaveAccountCopyWithImpl(this._self, this._then);

  final BridgeConfigurationMutation_SaveAccount _self;
  final $Res Function(BridgeConfigurationMutation_SaveAccount) _then;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? input = null,}) {
  return _then(BridgeConfigurationMutation_SaveAccount(
input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as AccountSettingsInput,
  ));
}


}

/// @nodoc


class BridgeConfigurationMutation_SetDefaultAccount extends BridgeConfigurationMutation {
  const BridgeConfigurationMutation_SetDefaultAccount({required this.accountId}): super._();


 final  String accountId;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationMutation_SetDefaultAccountCopyWith<BridgeConfigurationMutation_SetDefaultAccount> get copyWith => _$BridgeConfigurationMutation_SetDefaultAccountCopyWithImpl<BridgeConfigurationMutation_SetDefaultAccount>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationMutation_SetDefaultAccount&&(identical(other.accountId, accountId) || other.accountId == accountId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId);
}

@override
String toString() {
    return 'BridgeConfigurationMutation.setDefaultAccount(accountId: $accountId)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationMutation_SetDefaultAccountCopyWith<$Res> implements $BridgeConfigurationMutationCopyWith<$Res> {
  factory $BridgeConfigurationMutation_SetDefaultAccountCopyWith(BridgeConfigurationMutation_SetDefaultAccount value, $Res Function(BridgeConfigurationMutation_SetDefaultAccount) _then) = _$BridgeConfigurationMutation_SetDefaultAccountCopyWithImpl;
@useResult
$Res call({
 String accountId
});




}
/// @nodoc
class _$BridgeConfigurationMutation_SetDefaultAccountCopyWithImpl<$Res>
    implements $BridgeConfigurationMutation_SetDefaultAccountCopyWith<$Res> {
  _$BridgeConfigurationMutation_SetDefaultAccountCopyWithImpl(this._self, this._then);

  final BridgeConfigurationMutation_SetDefaultAccount _self;
  final $Res Function(BridgeConfigurationMutation_SetDefaultAccount) _then;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? accountId = null,}) {
  return _then(BridgeConfigurationMutation_SetDefaultAccount(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeConfigurationMutation_RemoveAccount extends BridgeConfigurationMutation {
  const BridgeConfigurationMutation_RemoveAccount({required this.accountId, this.replacementAccountId}): super._();


 final  String accountId;
 final  String? replacementAccountId;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationMutation_RemoveAccountCopyWith<BridgeConfigurationMutation_RemoveAccount> get copyWith => _$BridgeConfigurationMutation_RemoveAccountCopyWithImpl<BridgeConfigurationMutation_RemoveAccount>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationMutation_RemoveAccount&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.replacementAccountId, replacementAccountId) || other.replacementAccountId == replacementAccountId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,replacementAccountId);
}

@override
String toString() {
    return 'BridgeConfigurationMutation.removeAccount(accountId: $accountId, replacementAccountId: $replacementAccountId)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationMutation_RemoveAccountCopyWith<$Res> implements $BridgeConfigurationMutationCopyWith<$Res> {
  factory $BridgeConfigurationMutation_RemoveAccountCopyWith(BridgeConfigurationMutation_RemoveAccount value, $Res Function(BridgeConfigurationMutation_RemoveAccount) _then) = _$BridgeConfigurationMutation_RemoveAccountCopyWithImpl;
@useResult
$Res call({
 String accountId, String? replacementAccountId
});




}
/// @nodoc
class _$BridgeConfigurationMutation_RemoveAccountCopyWithImpl<$Res>
    implements $BridgeConfigurationMutation_RemoveAccountCopyWith<$Res> {
  _$BridgeConfigurationMutation_RemoveAccountCopyWithImpl(this._self, this._then);

  final BridgeConfigurationMutation_RemoveAccount _self;
  final $Res Function(BridgeConfigurationMutation_RemoveAccount) _then;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? replacementAccountId = freezed,}) {
  return _then(BridgeConfigurationMutation_RemoveAccount(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,replacementAccountId: freezed == replacementAccountId ? _self.replacementAccountId : replacementAccountId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BridgeConfigurationMutation_RemoveAccountModel extends BridgeConfigurationMutation {
  const BridgeConfigurationMutation_RemoveAccountModel({required this.accountId, required this.modelId}): super._();


 final  String accountId;
 final  String modelId;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationMutation_RemoveAccountModelCopyWith<BridgeConfigurationMutation_RemoveAccountModel> get copyWith => _$BridgeConfigurationMutation_RemoveAccountModelCopyWithImpl<BridgeConfigurationMutation_RemoveAccountModel>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationMutation_RemoveAccountModel&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,modelId);
}

@override
String toString() {
    return 'BridgeConfigurationMutation.removeAccountModel(accountId: $accountId, modelId: $modelId)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationMutation_RemoveAccountModelCopyWith<$Res> implements $BridgeConfigurationMutationCopyWith<$Res> {
  factory $BridgeConfigurationMutation_RemoveAccountModelCopyWith(BridgeConfigurationMutation_RemoveAccountModel value, $Res Function(BridgeConfigurationMutation_RemoveAccountModel) _then) = _$BridgeConfigurationMutation_RemoveAccountModelCopyWithImpl;
@useResult
$Res call({
 String accountId, String modelId
});




}
/// @nodoc
class _$BridgeConfigurationMutation_RemoveAccountModelCopyWithImpl<$Res>
    implements $BridgeConfigurationMutation_RemoveAccountModelCopyWith<$Res> {
  _$BridgeConfigurationMutation_RemoveAccountModelCopyWithImpl(this._self, this._then);

  final BridgeConfigurationMutation_RemoveAccountModel _self;
  final $Res Function(BridgeConfigurationMutation_RemoveAccountModel) _then;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? modelId = null,}) {
  return _then(BridgeConfigurationMutation_RemoveAccountModel(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeConfigurationMutation_SetAccountModelEnabled extends BridgeConfigurationMutation {
  const BridgeConfigurationMutation_SetAccountModelEnabled({required this.accountId, required this.modelId, required this.enabled}): super._();


 final  String accountId;
 final  String modelId;
 final  bool enabled;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationMutation_SetAccountModelEnabledCopyWith<BridgeConfigurationMutation_SetAccountModelEnabled> get copyWith => _$BridgeConfigurationMutation_SetAccountModelEnabledCopyWithImpl<BridgeConfigurationMutation_SetAccountModelEnabled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationMutation_SetAccountModelEnabled&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.enabled, enabled) || other.enabled == enabled));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,modelId,enabled);
}

@override
String toString() {
    return 'BridgeConfigurationMutation.setAccountModelEnabled(accountId: $accountId, modelId: $modelId, enabled: $enabled)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationMutation_SetAccountModelEnabledCopyWith<$Res> implements $BridgeConfigurationMutationCopyWith<$Res> {
  factory $BridgeConfigurationMutation_SetAccountModelEnabledCopyWith(BridgeConfigurationMutation_SetAccountModelEnabled value, $Res Function(BridgeConfigurationMutation_SetAccountModelEnabled) _then) = _$BridgeConfigurationMutation_SetAccountModelEnabledCopyWithImpl;
@useResult
$Res call({
 String accountId, String modelId, bool enabled
});




}
/// @nodoc
class _$BridgeConfigurationMutation_SetAccountModelEnabledCopyWithImpl<$Res>
    implements $BridgeConfigurationMutation_SetAccountModelEnabledCopyWith<$Res> {
  _$BridgeConfigurationMutation_SetAccountModelEnabledCopyWithImpl(this._self, this._then);

  final BridgeConfigurationMutation_SetAccountModelEnabled _self;
  final $Res Function(BridgeConfigurationMutation_SetAccountModelEnabled) _then;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? modelId = null,Object? enabled = null,}) {
  return _then(BridgeConfigurationMutation_SetAccountModelEnabled(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgeConfigurationMutation_SetAccountBillingKind extends BridgeConfigurationMutation {
  const BridgeConfigurationMutation_SetAccountBillingKind({required this.accountId, this.billingKind}): super._();


 final  String accountId;
 final  BridgeBillingKind? billingKind;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationMutation_SetAccountBillingKindCopyWith<BridgeConfigurationMutation_SetAccountBillingKind> get copyWith => _$BridgeConfigurationMutation_SetAccountBillingKindCopyWithImpl<BridgeConfigurationMutation_SetAccountBillingKind>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationMutation_SetAccountBillingKind&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.billingKind, billingKind) || other.billingKind == billingKind));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,billingKind);
}

@override
String toString() {
    return 'BridgeConfigurationMutation.setAccountBillingKind(accountId: $accountId, billingKind: $billingKind)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationMutation_SetAccountBillingKindCopyWith<$Res> implements $BridgeConfigurationMutationCopyWith<$Res> {
  factory $BridgeConfigurationMutation_SetAccountBillingKindCopyWith(BridgeConfigurationMutation_SetAccountBillingKind value, $Res Function(BridgeConfigurationMutation_SetAccountBillingKind) _then) = _$BridgeConfigurationMutation_SetAccountBillingKindCopyWithImpl;
@useResult
$Res call({
 String accountId, BridgeBillingKind? billingKind
});




}
/// @nodoc
class _$BridgeConfigurationMutation_SetAccountBillingKindCopyWithImpl<$Res>
    implements $BridgeConfigurationMutation_SetAccountBillingKindCopyWith<$Res> {
  _$BridgeConfigurationMutation_SetAccountBillingKindCopyWithImpl(this._self, this._then);

  final BridgeConfigurationMutation_SetAccountBillingKind _self;
  final $Res Function(BridgeConfigurationMutation_SetAccountBillingKind) _then;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? billingKind = freezed,}) {
  return _then(BridgeConfigurationMutation_SetAccountBillingKind(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,billingKind: freezed == billingKind ? _self.billingKind : billingKind // ignore: cast_nullable_to_non_nullable
as BridgeBillingKind?,
  ));
}


}

/// @nodoc


class BridgeConfigurationMutation_ApplyField extends BridgeConfigurationMutation {
  const BridgeConfigurationMutation_ApplyField({required this.update}): super._();


 final  SettingsFieldInput update;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationMutation_ApplyFieldCopyWith<BridgeConfigurationMutation_ApplyField> get copyWith => _$BridgeConfigurationMutation_ApplyFieldCopyWithImpl<BridgeConfigurationMutation_ApplyField>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationMutation_ApplyField&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,update);
}

@override
String toString() {
    return 'BridgeConfigurationMutation.applyField(update: $update)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationMutation_ApplyFieldCopyWith<$Res> implements $BridgeConfigurationMutationCopyWith<$Res> {
  factory $BridgeConfigurationMutation_ApplyFieldCopyWith(BridgeConfigurationMutation_ApplyField value, $Res Function(BridgeConfigurationMutation_ApplyField) _then) = _$BridgeConfigurationMutation_ApplyFieldCopyWithImpl;
@useResult
$Res call({
 SettingsFieldInput update
});


$SettingsFieldInputCopyWith<$Res> get update;

}
/// @nodoc
class _$BridgeConfigurationMutation_ApplyFieldCopyWithImpl<$Res>
    implements $BridgeConfigurationMutation_ApplyFieldCopyWith<$Res> {
  _$BridgeConfigurationMutation_ApplyFieldCopyWithImpl(this._self, this._then);

  final BridgeConfigurationMutation_ApplyField _self;
  final $Res Function(BridgeConfigurationMutation_ApplyField) _then;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? update = null,}) {
  return _then(BridgeConfigurationMutation_ApplyField(
update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as SettingsFieldInput,
  ));
}

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsFieldInputCopyWith<$Res> get update {

  return $SettingsFieldInputCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class BridgeConfigurationMutation_SetPermission extends BridgeConfigurationMutation {
  const BridgeConfigurationMutation_SetPermission({required this.mode}): super._();


 final  String mode;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationMutation_SetPermissionCopyWith<BridgeConfigurationMutation_SetPermission> get copyWith => _$BridgeConfigurationMutation_SetPermissionCopyWithImpl<BridgeConfigurationMutation_SetPermission>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationMutation_SetPermission&&(identical(other.mode, mode) || other.mode == mode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mode);
}

@override
String toString() {
    return 'BridgeConfigurationMutation.setPermission(mode: $mode)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationMutation_SetPermissionCopyWith<$Res> implements $BridgeConfigurationMutationCopyWith<$Res> {
  factory $BridgeConfigurationMutation_SetPermissionCopyWith(BridgeConfigurationMutation_SetPermission value, $Res Function(BridgeConfigurationMutation_SetPermission) _then) = _$BridgeConfigurationMutation_SetPermissionCopyWithImpl;
@useResult
$Res call({
 String mode
});




}
/// @nodoc
class _$BridgeConfigurationMutation_SetPermissionCopyWithImpl<$Res>
    implements $BridgeConfigurationMutation_SetPermissionCopyWith<$Res> {
  _$BridgeConfigurationMutation_SetPermissionCopyWithImpl(this._self, this._then);

  final BridgeConfigurationMutation_SetPermission _self;
  final $Res Function(BridgeConfigurationMutation_SetPermission) _then;

/// Create a copy of BridgeConfigurationMutation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? mode = null,}) {
  return _then(BridgeConfigurationMutation_SetPermission(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
