// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'configuration_acp_commands.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAcpAccountCommandOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAccountCommandOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpAccountCommandOutcome()';
}


}

/// @nodoc
class $BridgeAcpAccountCommandOutcomeCopyWith<$Res>  {
$BridgeAcpAccountCommandOutcomeCopyWith(BridgeAcpAccountCommandOutcome _, $Res Function(BridgeAcpAccountCommandOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpAccountCommandOutcome].
extension BridgeAcpAccountCommandOutcomePatterns on BridgeAcpAccountCommandOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpAccountCommandOutcome_Committed value)?  committed,TResult Function( BridgeAcpAccountCommandOutcome_CommittedButUnobserved value)?  committedButUnobserved,TResult Function( BridgeAcpAccountCommandOutcome_Rejected value)?  rejected,TResult Function( BridgeAcpAccountCommandOutcome_Unknown value)?  unknown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpAccountCommandOutcome_Committed() when committed != null:
return committed(_that);case BridgeAcpAccountCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that);case BridgeAcpAccountCommandOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeAcpAccountCommandOutcome_Unknown() when unknown != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpAccountCommandOutcome_Committed value)  committed,required TResult Function( BridgeAcpAccountCommandOutcome_CommittedButUnobserved value)  committedButUnobserved,required TResult Function( BridgeAcpAccountCommandOutcome_Rejected value)  rejected,required TResult Function( BridgeAcpAccountCommandOutcome_Unknown value)  unknown,}){
final _that = this;
switch (_that) {
case BridgeAcpAccountCommandOutcome_Committed():
return committed(_that);case BridgeAcpAccountCommandOutcome_CommittedButUnobserved():
return committedButUnobserved(_that);case BridgeAcpAccountCommandOutcome_Rejected():
return rejected(_that);case BridgeAcpAccountCommandOutcome_Unknown():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpAccountCommandOutcome_Committed value)?  committed,TResult? Function( BridgeAcpAccountCommandOutcome_CommittedButUnobserved value)?  committedButUnobserved,TResult? Function( BridgeAcpAccountCommandOutcome_Rejected value)?  rejected,TResult? Function( BridgeAcpAccountCommandOutcome_Unknown value)?  unknown,}){
final _that = this;
switch (_that) {
case BridgeAcpAccountCommandOutcome_Committed() when committed != null:
return committed(_that);case BridgeAcpAccountCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that);case BridgeAcpAccountCommandOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeAcpAccountCommandOutcome_Unknown() when unknown != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAcpAccountCommandReply reply)?  committed,TResult Function( BridgeStudioCommandReceipt receipt,  BridgeError error)?  committedButUnobserved,TResult Function( String operationId,  BridgeError error)?  rejected,TResult Function( String operationId,  BridgeError error)?  unknown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpAccountCommandOutcome_Committed() when committed != null:
return committed(_that.reply);case BridgeAcpAccountCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that.receipt,_that.error);case BridgeAcpAccountCommandOutcome_Rejected() when rejected != null:
return rejected(_that.operationId,_that.error);case BridgeAcpAccountCommandOutcome_Unknown() when unknown != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAcpAccountCommandReply reply)  committed,required TResult Function( BridgeStudioCommandReceipt receipt,  BridgeError error)  committedButUnobserved,required TResult Function( String operationId,  BridgeError error)  rejected,required TResult Function( String operationId,  BridgeError error)  unknown,}) {final _that = this;
switch (_that) {
case BridgeAcpAccountCommandOutcome_Committed():
return committed(_that.reply);case BridgeAcpAccountCommandOutcome_CommittedButUnobserved():
return committedButUnobserved(_that.receipt,_that.error);case BridgeAcpAccountCommandOutcome_Rejected():
return rejected(_that.operationId,_that.error);case BridgeAcpAccountCommandOutcome_Unknown():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAcpAccountCommandReply reply)?  committed,TResult? Function( BridgeStudioCommandReceipt receipt,  BridgeError error)?  committedButUnobserved,TResult? Function( String operationId,  BridgeError error)?  rejected,TResult? Function( String operationId,  BridgeError error)?  unknown,}) {final _that = this;
switch (_that) {
case BridgeAcpAccountCommandOutcome_Committed() when committed != null:
return committed(_that.reply);case BridgeAcpAccountCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that.receipt,_that.error);case BridgeAcpAccountCommandOutcome_Rejected() when rejected != null:
return rejected(_that.operationId,_that.error);case BridgeAcpAccountCommandOutcome_Unknown() when unknown != null:
return unknown(_that.operationId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpAccountCommandOutcome_Committed extends BridgeAcpAccountCommandOutcome {
  const BridgeAcpAccountCommandOutcome_Committed({required this.reply}): super._();


 final  BridgeAcpAccountCommandReply reply;

/// Create a copy of BridgeAcpAccountCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAccountCommandOutcome_CommittedCopyWith<BridgeAcpAccountCommandOutcome_Committed> get copyWith => _$BridgeAcpAccountCommandOutcome_CommittedCopyWithImpl<BridgeAcpAccountCommandOutcome_Committed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAccountCommandOutcome_Committed&&(identical(other.reply, reply) || other.reply == reply));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reply);
}

@override
String toString() {
    return 'BridgeAcpAccountCommandOutcome.committed(reply: $reply)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAccountCommandOutcome_CommittedCopyWith<$Res> implements $BridgeAcpAccountCommandOutcomeCopyWith<$Res> {
  factory $BridgeAcpAccountCommandOutcome_CommittedCopyWith(BridgeAcpAccountCommandOutcome_Committed value, $Res Function(BridgeAcpAccountCommandOutcome_Committed) _then) = _$BridgeAcpAccountCommandOutcome_CommittedCopyWithImpl;
@useResult
$Res call({
 BridgeAcpAccountCommandReply reply
});




}
/// @nodoc
class _$BridgeAcpAccountCommandOutcome_CommittedCopyWithImpl<$Res>
    implements $BridgeAcpAccountCommandOutcome_CommittedCopyWith<$Res> {
  _$BridgeAcpAccountCommandOutcome_CommittedCopyWithImpl(this._self, this._then);

  final BridgeAcpAccountCommandOutcome_Committed _self;
  final $Res Function(BridgeAcpAccountCommandOutcome_Committed) _then;

/// Create a copy of BridgeAcpAccountCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reply = null,}) {
  return _then(BridgeAcpAccountCommandOutcome_Committed(
reply: null == reply ? _self.reply : reply // ignore: cast_nullable_to_non_nullable
as BridgeAcpAccountCommandReply,
  ));
}


}

/// @nodoc


class BridgeAcpAccountCommandOutcome_CommittedButUnobserved extends BridgeAcpAccountCommandOutcome {
  const BridgeAcpAccountCommandOutcome_CommittedButUnobserved({required this.receipt, required this.error}): super._();


 final  BridgeStudioCommandReceipt receipt;
 final  BridgeError error;

/// Create a copy of BridgeAcpAccountCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAccountCommandOutcome_CommittedButUnobservedCopyWith<BridgeAcpAccountCommandOutcome_CommittedButUnobserved> get copyWith => _$BridgeAcpAccountCommandOutcome_CommittedButUnobservedCopyWithImpl<BridgeAcpAccountCommandOutcome_CommittedButUnobserved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAccountCommandOutcome_CommittedButUnobserved&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receipt,error);
}

@override
String toString() {
    return 'BridgeAcpAccountCommandOutcome.committedButUnobserved(receipt: $receipt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAccountCommandOutcome_CommittedButUnobservedCopyWith<$Res> implements $BridgeAcpAccountCommandOutcomeCopyWith<$Res> {
  factory $BridgeAcpAccountCommandOutcome_CommittedButUnobservedCopyWith(BridgeAcpAccountCommandOutcome_CommittedButUnobserved value, $Res Function(BridgeAcpAccountCommandOutcome_CommittedButUnobserved) _then) = _$BridgeAcpAccountCommandOutcome_CommittedButUnobservedCopyWithImpl;
@useResult
$Res call({
 BridgeStudioCommandReceipt receipt, BridgeError error
});




}
/// @nodoc
class _$BridgeAcpAccountCommandOutcome_CommittedButUnobservedCopyWithImpl<$Res>
    implements $BridgeAcpAccountCommandOutcome_CommittedButUnobservedCopyWith<$Res> {
  _$BridgeAcpAccountCommandOutcome_CommittedButUnobservedCopyWithImpl(this._self, this._then);

  final BridgeAcpAccountCommandOutcome_CommittedButUnobserved _self;
  final $Res Function(BridgeAcpAccountCommandOutcome_CommittedButUnobserved) _then;

/// Create a copy of BridgeAcpAccountCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? receipt = null,Object? error = null,}) {
  return _then(BridgeAcpAccountCommandOutcome_CommittedButUnobserved(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as BridgeStudioCommandReceipt,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeAcpAccountCommandOutcome_Rejected extends BridgeAcpAccountCommandOutcome {
  const BridgeAcpAccountCommandOutcome_Rejected({required this.operationId, required this.error}): super._();


 final  String operationId;
 final  BridgeError error;

/// Create a copy of BridgeAcpAccountCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAccountCommandOutcome_RejectedCopyWith<BridgeAcpAccountCommandOutcome_Rejected> get copyWith => _$BridgeAcpAccountCommandOutcome_RejectedCopyWithImpl<BridgeAcpAccountCommandOutcome_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAccountCommandOutcome_Rejected&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,error);
}

@override
String toString() {
    return 'BridgeAcpAccountCommandOutcome.rejected(operationId: $operationId, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAccountCommandOutcome_RejectedCopyWith<$Res> implements $BridgeAcpAccountCommandOutcomeCopyWith<$Res> {
  factory $BridgeAcpAccountCommandOutcome_RejectedCopyWith(BridgeAcpAccountCommandOutcome_Rejected value, $Res Function(BridgeAcpAccountCommandOutcome_Rejected) _then) = _$BridgeAcpAccountCommandOutcome_RejectedCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeError error
});




}
/// @nodoc
class _$BridgeAcpAccountCommandOutcome_RejectedCopyWithImpl<$Res>
    implements $BridgeAcpAccountCommandOutcome_RejectedCopyWith<$Res> {
  _$BridgeAcpAccountCommandOutcome_RejectedCopyWithImpl(this._self, this._then);

  final BridgeAcpAccountCommandOutcome_Rejected _self;
  final $Res Function(BridgeAcpAccountCommandOutcome_Rejected) _then;

/// Create a copy of BridgeAcpAccountCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? error = null,}) {
  return _then(BridgeAcpAccountCommandOutcome_Rejected(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeAcpAccountCommandOutcome_Unknown extends BridgeAcpAccountCommandOutcome {
  const BridgeAcpAccountCommandOutcome_Unknown({required this.operationId, required this.error}): super._();


 final  String operationId;
 final  BridgeError error;

/// Create a copy of BridgeAcpAccountCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAccountCommandOutcome_UnknownCopyWith<BridgeAcpAccountCommandOutcome_Unknown> get copyWith => _$BridgeAcpAccountCommandOutcome_UnknownCopyWithImpl<BridgeAcpAccountCommandOutcome_Unknown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAccountCommandOutcome_Unknown&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,error);
}

@override
String toString() {
    return 'BridgeAcpAccountCommandOutcome.unknown(operationId: $operationId, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAccountCommandOutcome_UnknownCopyWith<$Res> implements $BridgeAcpAccountCommandOutcomeCopyWith<$Res> {
  factory $BridgeAcpAccountCommandOutcome_UnknownCopyWith(BridgeAcpAccountCommandOutcome_Unknown value, $Res Function(BridgeAcpAccountCommandOutcome_Unknown) _then) = _$BridgeAcpAccountCommandOutcome_UnknownCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeError error
});




}
/// @nodoc
class _$BridgeAcpAccountCommandOutcome_UnknownCopyWithImpl<$Res>
    implements $BridgeAcpAccountCommandOutcome_UnknownCopyWith<$Res> {
  _$BridgeAcpAccountCommandOutcome_UnknownCopyWithImpl(this._self, this._then);

  final BridgeAcpAccountCommandOutcome_Unknown _self;
  final $Res Function(BridgeAcpAccountCommandOutcome_Unknown) _then;

/// Create a copy of BridgeAcpAccountCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? error = null,}) {
  return _then(BridgeAcpAccountCommandOutcome_Unknown(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpAccountMutation {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAccountMutation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpAccountMutation()';
}


}

/// @nodoc
class $BridgeAcpAccountMutationCopyWith<$Res>  {
$BridgeAcpAccountMutationCopyWith(BridgeAcpAccountMutation _, $Res Function(BridgeAcpAccountMutation) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpAccountMutation].
extension BridgeAcpAccountMutationPatterns on BridgeAcpAccountMutation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpAccountMutation_SaveAccount value)?  saveAccount,TResult Function( BridgeAcpAccountMutation_RemoveAccount value)?  removeAccount,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpAccountMutation_SaveAccount() when saveAccount != null:
return saveAccount(_that);case BridgeAcpAccountMutation_RemoveAccount() when removeAccount != null:
return removeAccount(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpAccountMutation_SaveAccount value)  saveAccount,required TResult Function( BridgeAcpAccountMutation_RemoveAccount value)  removeAccount,}){
final _that = this;
switch (_that) {
case BridgeAcpAccountMutation_SaveAccount():
return saveAccount(_that);case BridgeAcpAccountMutation_RemoveAccount():
return removeAccount(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpAccountMutation_SaveAccount value)?  saveAccount,TResult? Function( BridgeAcpAccountMutation_RemoveAccount value)?  removeAccount,}){
final _that = this;
switch (_that) {
case BridgeAcpAccountMutation_SaveAccount() when saveAccount != null:
return saveAccount(_that);case BridgeAcpAccountMutation_RemoveAccount() when removeAccount != null:
return removeAccount(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAcpAccountUpdate input)?  saveAccount,TResult Function( String accountId)?  removeAccount,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpAccountMutation_SaveAccount() when saveAccount != null:
return saveAccount(_that.input);case BridgeAcpAccountMutation_RemoveAccount() when removeAccount != null:
return removeAccount(_that.accountId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAcpAccountUpdate input)  saveAccount,required TResult Function( String accountId)  removeAccount,}) {final _that = this;
switch (_that) {
case BridgeAcpAccountMutation_SaveAccount():
return saveAccount(_that.input);case BridgeAcpAccountMutation_RemoveAccount():
return removeAccount(_that.accountId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAcpAccountUpdate input)?  saveAccount,TResult? Function( String accountId)?  removeAccount,}) {final _that = this;
switch (_that) {
case BridgeAcpAccountMutation_SaveAccount() when saveAccount != null:
return saveAccount(_that.input);case BridgeAcpAccountMutation_RemoveAccount() when removeAccount != null:
return removeAccount(_that.accountId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpAccountMutation_SaveAccount extends BridgeAcpAccountMutation {
  const BridgeAcpAccountMutation_SaveAccount({required this.input}): super._();


 final  BridgeAcpAccountUpdate input;

/// Create a copy of BridgeAcpAccountMutation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAccountMutation_SaveAccountCopyWith<BridgeAcpAccountMutation_SaveAccount> get copyWith => _$BridgeAcpAccountMutation_SaveAccountCopyWithImpl<BridgeAcpAccountMutation_SaveAccount>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAccountMutation_SaveAccount&&(identical(other.input, input) || other.input == input));
}


@override
int get hashCode {
    return Object.hash(runtimeType,input);
}

@override
String toString() {
    return 'BridgeAcpAccountMutation.saveAccount(input: $input)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAccountMutation_SaveAccountCopyWith<$Res> implements $BridgeAcpAccountMutationCopyWith<$Res> {
  factory $BridgeAcpAccountMutation_SaveAccountCopyWith(BridgeAcpAccountMutation_SaveAccount value, $Res Function(BridgeAcpAccountMutation_SaveAccount) _then) = _$BridgeAcpAccountMutation_SaveAccountCopyWithImpl;
@useResult
$Res call({
 BridgeAcpAccountUpdate input
});




}
/// @nodoc
class _$BridgeAcpAccountMutation_SaveAccountCopyWithImpl<$Res>
    implements $BridgeAcpAccountMutation_SaveAccountCopyWith<$Res> {
  _$BridgeAcpAccountMutation_SaveAccountCopyWithImpl(this._self, this._then);

  final BridgeAcpAccountMutation_SaveAccount _self;
  final $Res Function(BridgeAcpAccountMutation_SaveAccount) _then;

/// Create a copy of BridgeAcpAccountMutation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? input = null,}) {
  return _then(BridgeAcpAccountMutation_SaveAccount(
input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as BridgeAcpAccountUpdate,
  ));
}


}

/// @nodoc


class BridgeAcpAccountMutation_RemoveAccount extends BridgeAcpAccountMutation {
  const BridgeAcpAccountMutation_RemoveAccount({required this.accountId}): super._();


 final  String accountId;

/// Create a copy of BridgeAcpAccountMutation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAccountMutation_RemoveAccountCopyWith<BridgeAcpAccountMutation_RemoveAccount> get copyWith => _$BridgeAcpAccountMutation_RemoveAccountCopyWithImpl<BridgeAcpAccountMutation_RemoveAccount>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAccountMutation_RemoveAccount&&(identical(other.accountId, accountId) || other.accountId == accountId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId);
}

@override
String toString() {
    return 'BridgeAcpAccountMutation.removeAccount(accountId: $accountId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAccountMutation_RemoveAccountCopyWith<$Res> implements $BridgeAcpAccountMutationCopyWith<$Res> {
  factory $BridgeAcpAccountMutation_RemoveAccountCopyWith(BridgeAcpAccountMutation_RemoveAccount value, $Res Function(BridgeAcpAccountMutation_RemoveAccount) _then) = _$BridgeAcpAccountMutation_RemoveAccountCopyWithImpl;
@useResult
$Res call({
 String accountId
});




}
/// @nodoc
class _$BridgeAcpAccountMutation_RemoveAccountCopyWithImpl<$Res>
    implements $BridgeAcpAccountMutation_RemoveAccountCopyWith<$Res> {
  _$BridgeAcpAccountMutation_RemoveAccountCopyWithImpl(this._self, this._then);

  final BridgeAcpAccountMutation_RemoveAccount _self;
  final $Res Function(BridgeAcpAccountMutation_RemoveAccount) _then;

/// Create a copy of BridgeAcpAccountMutation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? accountId = null,}) {
  return _then(BridgeAcpAccountMutation_RemoveAccount(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
