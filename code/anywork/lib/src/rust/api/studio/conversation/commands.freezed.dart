// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'commands.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeSubmitPromptOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSubmitPromptOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeSubmitPromptOutcome()';
}


}

/// @nodoc
class $BridgeSubmitPromptOutcomeCopyWith<$Res>  {
$BridgeSubmitPromptOutcomeCopyWith(BridgeSubmitPromptOutcome _, $Res Function(BridgeSubmitPromptOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeSubmitPromptOutcome].
extension BridgeSubmitPromptOutcomePatterns on BridgeSubmitPromptOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSubmitPromptOutcome_Returned value)?  returned,TResult Function( BridgeSubmitPromptOutcome_Rejected value)?  rejected,TResult Function( BridgeSubmitPromptOutcome_UnknownOutcome value)?  unknownOutcome,TResult Function( BridgeSubmitPromptOutcome_CommittedButUnobserved value)?  committedButUnobserved,TResult Function( BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt value)?  confirmedWithoutReceipt,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSubmitPromptOutcome_Returned() when returned != null:
return returned(_that);case BridgeSubmitPromptOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeSubmitPromptOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that);case BridgeSubmitPromptOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that);case BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt() when confirmedWithoutReceipt != null:
return confirmedWithoutReceipt(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSubmitPromptOutcome_Returned value)  returned,required TResult Function( BridgeSubmitPromptOutcome_Rejected value)  rejected,required TResult Function( BridgeSubmitPromptOutcome_UnknownOutcome value)  unknownOutcome,required TResult Function( BridgeSubmitPromptOutcome_CommittedButUnobserved value)  committedButUnobserved,required TResult Function( BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt value)  confirmedWithoutReceipt,}){
final _that = this;
switch (_that) {
case BridgeSubmitPromptOutcome_Returned():
return returned(_that);case BridgeSubmitPromptOutcome_Rejected():
return rejected(_that);case BridgeSubmitPromptOutcome_UnknownOutcome():
return unknownOutcome(_that);case BridgeSubmitPromptOutcome_CommittedButUnobserved():
return committedButUnobserved(_that);case BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt():
return confirmedWithoutReceipt(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSubmitPromptOutcome_Returned value)?  returned,TResult? Function( BridgeSubmitPromptOutcome_Rejected value)?  rejected,TResult? Function( BridgeSubmitPromptOutcome_UnknownOutcome value)?  unknownOutcome,TResult? Function( BridgeSubmitPromptOutcome_CommittedButUnobserved value)?  committedButUnobserved,TResult? Function( BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt value)?  confirmedWithoutReceipt,}){
final _that = this;
switch (_that) {
case BridgeSubmitPromptOutcome_Returned() when returned != null:
return returned(_that);case BridgeSubmitPromptOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeSubmitPromptOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that);case BridgeSubmitPromptOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that);case BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt() when confirmedWithoutReceipt != null:
return confirmedWithoutReceipt(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( SubmitPromptResponse value)?  returned,TResult Function( BridgeError error)?  rejected,TResult Function( BridgeError error)?  unknownOutcome,TResult Function( BridgeStudioCommandReceipt receipt,  BridgeError error)?  committedButUnobserved,TResult Function( BridgeError error)?  confirmedWithoutReceipt,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSubmitPromptOutcome_Returned() when returned != null:
return returned(_that.value);case BridgeSubmitPromptOutcome_Rejected() when rejected != null:
return rejected(_that.error);case BridgeSubmitPromptOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that.error);case BridgeSubmitPromptOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that.receipt,_that.error);case BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt() when confirmedWithoutReceipt != null:
return confirmedWithoutReceipt(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( SubmitPromptResponse value)  returned,required TResult Function( BridgeError error)  rejected,required TResult Function( BridgeError error)  unknownOutcome,required TResult Function( BridgeStudioCommandReceipt receipt,  BridgeError error)  committedButUnobserved,required TResult Function( BridgeError error)  confirmedWithoutReceipt,}) {final _that = this;
switch (_that) {
case BridgeSubmitPromptOutcome_Returned():
return returned(_that.value);case BridgeSubmitPromptOutcome_Rejected():
return rejected(_that.error);case BridgeSubmitPromptOutcome_UnknownOutcome():
return unknownOutcome(_that.error);case BridgeSubmitPromptOutcome_CommittedButUnobserved():
return committedButUnobserved(_that.receipt,_that.error);case BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt():
return confirmedWithoutReceipt(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( SubmitPromptResponse value)?  returned,TResult? Function( BridgeError error)?  rejected,TResult? Function( BridgeError error)?  unknownOutcome,TResult? Function( BridgeStudioCommandReceipt receipt,  BridgeError error)?  committedButUnobserved,TResult? Function( BridgeError error)?  confirmedWithoutReceipt,}) {final _that = this;
switch (_that) {
case BridgeSubmitPromptOutcome_Returned() when returned != null:
return returned(_that.value);case BridgeSubmitPromptOutcome_Rejected() when rejected != null:
return rejected(_that.error);case BridgeSubmitPromptOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that.error);case BridgeSubmitPromptOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that.receipt,_that.error);case BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt() when confirmedWithoutReceipt != null:
return confirmedWithoutReceipt(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSubmitPromptOutcome_Returned extends BridgeSubmitPromptOutcome {
  const BridgeSubmitPromptOutcome_Returned({required this.value}): super._();


 final  SubmitPromptResponse value;

/// Create a copy of BridgeSubmitPromptOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSubmitPromptOutcome_ReturnedCopyWith<BridgeSubmitPromptOutcome_Returned> get copyWith => _$BridgeSubmitPromptOutcome_ReturnedCopyWithImpl<BridgeSubmitPromptOutcome_Returned>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSubmitPromptOutcome_Returned&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeSubmitPromptOutcome.returned(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeSubmitPromptOutcome_ReturnedCopyWith<$Res> implements $BridgeSubmitPromptOutcomeCopyWith<$Res> {
  factory $BridgeSubmitPromptOutcome_ReturnedCopyWith(BridgeSubmitPromptOutcome_Returned value, $Res Function(BridgeSubmitPromptOutcome_Returned) _then) = _$BridgeSubmitPromptOutcome_ReturnedCopyWithImpl;
@useResult
$Res call({
 SubmitPromptResponse value
});




}
/// @nodoc
class _$BridgeSubmitPromptOutcome_ReturnedCopyWithImpl<$Res>
    implements $BridgeSubmitPromptOutcome_ReturnedCopyWith<$Res> {
  _$BridgeSubmitPromptOutcome_ReturnedCopyWithImpl(this._self, this._then);

  final BridgeSubmitPromptOutcome_Returned _self;
  final $Res Function(BridgeSubmitPromptOutcome_Returned) _then;

/// Create a copy of BridgeSubmitPromptOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeSubmitPromptOutcome_Returned(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SubmitPromptResponse,
  ));
}


}

/// @nodoc


class BridgeSubmitPromptOutcome_Rejected extends BridgeSubmitPromptOutcome {
  const BridgeSubmitPromptOutcome_Rejected({required this.error}): super._();


 final  BridgeError error;

/// Create a copy of BridgeSubmitPromptOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSubmitPromptOutcome_RejectedCopyWith<BridgeSubmitPromptOutcome_Rejected> get copyWith => _$BridgeSubmitPromptOutcome_RejectedCopyWithImpl<BridgeSubmitPromptOutcome_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSubmitPromptOutcome_Rejected&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeSubmitPromptOutcome.rejected(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeSubmitPromptOutcome_RejectedCopyWith<$Res> implements $BridgeSubmitPromptOutcomeCopyWith<$Res> {
  factory $BridgeSubmitPromptOutcome_RejectedCopyWith(BridgeSubmitPromptOutcome_Rejected value, $Res Function(BridgeSubmitPromptOutcome_Rejected) _then) = _$BridgeSubmitPromptOutcome_RejectedCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeSubmitPromptOutcome_RejectedCopyWithImpl<$Res>
    implements $BridgeSubmitPromptOutcome_RejectedCopyWith<$Res> {
  _$BridgeSubmitPromptOutcome_RejectedCopyWithImpl(this._self, this._then);

  final BridgeSubmitPromptOutcome_Rejected _self;
  final $Res Function(BridgeSubmitPromptOutcome_Rejected) _then;

/// Create a copy of BridgeSubmitPromptOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeSubmitPromptOutcome_Rejected(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeSubmitPromptOutcome_UnknownOutcome extends BridgeSubmitPromptOutcome {
  const BridgeSubmitPromptOutcome_UnknownOutcome({required this.error}): super._();


 final  BridgeError error;

/// Create a copy of BridgeSubmitPromptOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSubmitPromptOutcome_UnknownOutcomeCopyWith<BridgeSubmitPromptOutcome_UnknownOutcome> get copyWith => _$BridgeSubmitPromptOutcome_UnknownOutcomeCopyWithImpl<BridgeSubmitPromptOutcome_UnknownOutcome>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSubmitPromptOutcome_UnknownOutcome&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeSubmitPromptOutcome.unknownOutcome(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeSubmitPromptOutcome_UnknownOutcomeCopyWith<$Res> implements $BridgeSubmitPromptOutcomeCopyWith<$Res> {
  factory $BridgeSubmitPromptOutcome_UnknownOutcomeCopyWith(BridgeSubmitPromptOutcome_UnknownOutcome value, $Res Function(BridgeSubmitPromptOutcome_UnknownOutcome) _then) = _$BridgeSubmitPromptOutcome_UnknownOutcomeCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeSubmitPromptOutcome_UnknownOutcomeCopyWithImpl<$Res>
    implements $BridgeSubmitPromptOutcome_UnknownOutcomeCopyWith<$Res> {
  _$BridgeSubmitPromptOutcome_UnknownOutcomeCopyWithImpl(this._self, this._then);

  final BridgeSubmitPromptOutcome_UnknownOutcome _self;
  final $Res Function(BridgeSubmitPromptOutcome_UnknownOutcome) _then;

/// Create a copy of BridgeSubmitPromptOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeSubmitPromptOutcome_UnknownOutcome(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeSubmitPromptOutcome_CommittedButUnobserved extends BridgeSubmitPromptOutcome {
  const BridgeSubmitPromptOutcome_CommittedButUnobserved({required this.receipt, required this.error}): super._();


 final  BridgeStudioCommandReceipt receipt;
 final  BridgeError error;

/// Create a copy of BridgeSubmitPromptOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSubmitPromptOutcome_CommittedButUnobservedCopyWith<BridgeSubmitPromptOutcome_CommittedButUnobserved> get copyWith => _$BridgeSubmitPromptOutcome_CommittedButUnobservedCopyWithImpl<BridgeSubmitPromptOutcome_CommittedButUnobserved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSubmitPromptOutcome_CommittedButUnobserved&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receipt,error);
}

@override
String toString() {
    return 'BridgeSubmitPromptOutcome.committedButUnobserved(receipt: $receipt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeSubmitPromptOutcome_CommittedButUnobservedCopyWith<$Res> implements $BridgeSubmitPromptOutcomeCopyWith<$Res> {
  factory $BridgeSubmitPromptOutcome_CommittedButUnobservedCopyWith(BridgeSubmitPromptOutcome_CommittedButUnobserved value, $Res Function(BridgeSubmitPromptOutcome_CommittedButUnobserved) _then) = _$BridgeSubmitPromptOutcome_CommittedButUnobservedCopyWithImpl;
@useResult
$Res call({
 BridgeStudioCommandReceipt receipt, BridgeError error
});




}
/// @nodoc
class _$BridgeSubmitPromptOutcome_CommittedButUnobservedCopyWithImpl<$Res>
    implements $BridgeSubmitPromptOutcome_CommittedButUnobservedCopyWith<$Res> {
  _$BridgeSubmitPromptOutcome_CommittedButUnobservedCopyWithImpl(this._self, this._then);

  final BridgeSubmitPromptOutcome_CommittedButUnobserved _self;
  final $Res Function(BridgeSubmitPromptOutcome_CommittedButUnobserved) _then;

/// Create a copy of BridgeSubmitPromptOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? receipt = null,Object? error = null,}) {
  return _then(BridgeSubmitPromptOutcome_CommittedButUnobserved(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as BridgeStudioCommandReceipt,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt extends BridgeSubmitPromptOutcome {
  const BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt({required this.error}): super._();


 final  BridgeError error;

/// Create a copy of BridgeSubmitPromptOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSubmitPromptOutcome_ConfirmedWithoutReceiptCopyWith<BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt> get copyWith => _$BridgeSubmitPromptOutcome_ConfirmedWithoutReceiptCopyWithImpl<BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeSubmitPromptOutcome.confirmedWithoutReceipt(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeSubmitPromptOutcome_ConfirmedWithoutReceiptCopyWith<$Res> implements $BridgeSubmitPromptOutcomeCopyWith<$Res> {
  factory $BridgeSubmitPromptOutcome_ConfirmedWithoutReceiptCopyWith(BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt value, $Res Function(BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt) _then) = _$BridgeSubmitPromptOutcome_ConfirmedWithoutReceiptCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeSubmitPromptOutcome_ConfirmedWithoutReceiptCopyWithImpl<$Res>
    implements $BridgeSubmitPromptOutcome_ConfirmedWithoutReceiptCopyWith<$Res> {
  _$BridgeSubmitPromptOutcome_ConfirmedWithoutReceiptCopyWithImpl(this._self, this._then);

  final BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt _self;
  final $Res Function(BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt) _then;

/// Create a copy of BridgeSubmitPromptOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeSubmitPromptOutcome_ConfirmedWithoutReceipt(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

// dart format on
