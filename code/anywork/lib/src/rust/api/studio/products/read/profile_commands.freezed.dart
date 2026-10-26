// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'profile_commands.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeConfigurationReloadOutcome {

 String get operationId;
/// Create a copy of BridgeConfigurationReloadOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationReloadOutcomeCopyWith<BridgeConfigurationReloadOutcome> get copyWith => _$BridgeConfigurationReloadOutcomeCopyWithImpl<BridgeConfigurationReloadOutcome>(this as BridgeConfigurationReloadOutcome, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeConfigurationReloadOutcome;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationReloadOutcome&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId));
}


@override
int get hashCode {
  final _this = this as BridgeConfigurationReloadOutcome;
  return Object.hash(runtimeType,_this.operationId);
}

@override
String toString() {
  final _this = this as BridgeConfigurationReloadOutcome;
  return 'BridgeConfigurationReloadOutcome(operationId: ${_this.operationId})';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationReloadOutcomeCopyWith<$Res>  {
  factory $BridgeConfigurationReloadOutcomeCopyWith(BridgeConfigurationReloadOutcome value, $Res Function(BridgeConfigurationReloadOutcome) _then) = _$BridgeConfigurationReloadOutcomeCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BridgeConfigurationReloadOutcomeCopyWithImpl<$Res>
    implements $BridgeConfigurationReloadOutcomeCopyWith<$Res> {
  _$BridgeConfigurationReloadOutcomeCopyWithImpl(this._self, this._then);

  final BridgeConfigurationReloadOutcome _self;
  final $Res Function(BridgeConfigurationReloadOutcome) _then;

/// Create a copy of BridgeConfigurationReloadOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,}) {
  return _then(_self.copyWith(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeConfigurationReloadOutcome].
extension BridgeConfigurationReloadOutcomePatterns on BridgeConfigurationReloadOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeConfigurationReloadOutcome_Returned value)?  returned,TResult Function( BridgeConfigurationReloadOutcome_AdoptedButUnobserved value)?  adoptedButUnobserved,TResult Function( BridgeConfigurationReloadOutcome_Rejected value)?  rejected,TResult Function( BridgeConfigurationReloadOutcome_Unknown value)?  unknown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeConfigurationReloadOutcome_Returned() when returned != null:
return returned(_that);case BridgeConfigurationReloadOutcome_AdoptedButUnobserved() when adoptedButUnobserved != null:
return adoptedButUnobserved(_that);case BridgeConfigurationReloadOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeConfigurationReloadOutcome_Unknown() when unknown != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeConfigurationReloadOutcome_Returned value)  returned,required TResult Function( BridgeConfigurationReloadOutcome_AdoptedButUnobserved value)  adoptedButUnobserved,required TResult Function( BridgeConfigurationReloadOutcome_Rejected value)  rejected,required TResult Function( BridgeConfigurationReloadOutcome_Unknown value)  unknown,}){
final _that = this;
switch (_that) {
case BridgeConfigurationReloadOutcome_Returned():
return returned(_that);case BridgeConfigurationReloadOutcome_AdoptedButUnobserved():
return adoptedButUnobserved(_that);case BridgeConfigurationReloadOutcome_Rejected():
return rejected(_that);case BridgeConfigurationReloadOutcome_Unknown():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeConfigurationReloadOutcome_Returned value)?  returned,TResult? Function( BridgeConfigurationReloadOutcome_AdoptedButUnobserved value)?  adoptedButUnobserved,TResult? Function( BridgeConfigurationReloadOutcome_Rejected value)?  rejected,TResult? Function( BridgeConfigurationReloadOutcome_Unknown value)?  unknown,}){
final _that = this;
switch (_that) {
case BridgeConfigurationReloadOutcome_Returned() when returned != null:
return returned(_that);case BridgeConfigurationReloadOutcome_AdoptedButUnobserved() when adoptedButUnobserved != null:
return adoptedButUnobserved(_that);case BridgeConfigurationReloadOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeConfigurationReloadOutcome_Unknown() when unknown != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String operationId,  BridgeConfigurationReloadResult result)?  returned,TResult Function( String operationId,  BridgeError error)?  adoptedButUnobserved,TResult Function( String operationId,  BridgeError error)?  rejected,TResult Function( String operationId,  BridgeError error)?  unknown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeConfigurationReloadOutcome_Returned() when returned != null:
return returned(_that.operationId,_that.result);case BridgeConfigurationReloadOutcome_AdoptedButUnobserved() when adoptedButUnobserved != null:
return adoptedButUnobserved(_that.operationId,_that.error);case BridgeConfigurationReloadOutcome_Rejected() when rejected != null:
return rejected(_that.operationId,_that.error);case BridgeConfigurationReloadOutcome_Unknown() when unknown != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String operationId,  BridgeConfigurationReloadResult result)  returned,required TResult Function( String operationId,  BridgeError error)  adoptedButUnobserved,required TResult Function( String operationId,  BridgeError error)  rejected,required TResult Function( String operationId,  BridgeError error)  unknown,}) {final _that = this;
switch (_that) {
case BridgeConfigurationReloadOutcome_Returned():
return returned(_that.operationId,_that.result);case BridgeConfigurationReloadOutcome_AdoptedButUnobserved():
return adoptedButUnobserved(_that.operationId,_that.error);case BridgeConfigurationReloadOutcome_Rejected():
return rejected(_that.operationId,_that.error);case BridgeConfigurationReloadOutcome_Unknown():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String operationId,  BridgeConfigurationReloadResult result)?  returned,TResult? Function( String operationId,  BridgeError error)?  adoptedButUnobserved,TResult? Function( String operationId,  BridgeError error)?  rejected,TResult? Function( String operationId,  BridgeError error)?  unknown,}) {final _that = this;
switch (_that) {
case BridgeConfigurationReloadOutcome_Returned() when returned != null:
return returned(_that.operationId,_that.result);case BridgeConfigurationReloadOutcome_AdoptedButUnobserved() when adoptedButUnobserved != null:
return adoptedButUnobserved(_that.operationId,_that.error);case BridgeConfigurationReloadOutcome_Rejected() when rejected != null:
return rejected(_that.operationId,_that.error);case BridgeConfigurationReloadOutcome_Unknown() when unknown != null:
return unknown(_that.operationId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeConfigurationReloadOutcome_Returned extends BridgeConfigurationReloadOutcome {
  const BridgeConfigurationReloadOutcome_Returned({required this.operationId, required this.result}): super._();


@override final  String operationId;
 final  BridgeConfigurationReloadResult result;

/// Create a copy of BridgeConfigurationReloadOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationReloadOutcome_ReturnedCopyWith<BridgeConfigurationReloadOutcome_Returned> get copyWith => _$BridgeConfigurationReloadOutcome_ReturnedCopyWithImpl<BridgeConfigurationReloadOutcome_Returned>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationReloadOutcome_Returned&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,result);
}

@override
String toString() {
    return 'BridgeConfigurationReloadOutcome.returned(operationId: $operationId, result: $result)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationReloadOutcome_ReturnedCopyWith<$Res> implements $BridgeConfigurationReloadOutcomeCopyWith<$Res> {
  factory $BridgeConfigurationReloadOutcome_ReturnedCopyWith(BridgeConfigurationReloadOutcome_Returned value, $Res Function(BridgeConfigurationReloadOutcome_Returned) _then) = _$BridgeConfigurationReloadOutcome_ReturnedCopyWithImpl;
@override @useResult
$Res call({
 String operationId, BridgeConfigurationReloadResult result
});




}
/// @nodoc
class _$BridgeConfigurationReloadOutcome_ReturnedCopyWithImpl<$Res>
    implements $BridgeConfigurationReloadOutcome_ReturnedCopyWith<$Res> {
  _$BridgeConfigurationReloadOutcome_ReturnedCopyWithImpl(this._self, this._then);

  final BridgeConfigurationReloadOutcome_Returned _self;
  final $Res Function(BridgeConfigurationReloadOutcome_Returned) _then;

/// Create a copy of BridgeConfigurationReloadOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? result = null,}) {
  return _then(BridgeConfigurationReloadOutcome_Returned(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as BridgeConfigurationReloadResult,
  ));
}


}

/// @nodoc


class BridgeConfigurationReloadOutcome_AdoptedButUnobserved extends BridgeConfigurationReloadOutcome {
  const BridgeConfigurationReloadOutcome_AdoptedButUnobserved({required this.operationId, required this.error}): super._();


@override final  String operationId;
 final  BridgeError error;

/// Create a copy of BridgeConfigurationReloadOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationReloadOutcome_AdoptedButUnobservedCopyWith<BridgeConfigurationReloadOutcome_AdoptedButUnobserved> get copyWith => _$BridgeConfigurationReloadOutcome_AdoptedButUnobservedCopyWithImpl<BridgeConfigurationReloadOutcome_AdoptedButUnobserved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationReloadOutcome_AdoptedButUnobserved&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,error);
}

@override
String toString() {
    return 'BridgeConfigurationReloadOutcome.adoptedButUnobserved(operationId: $operationId, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationReloadOutcome_AdoptedButUnobservedCopyWith<$Res> implements $BridgeConfigurationReloadOutcomeCopyWith<$Res> {
  factory $BridgeConfigurationReloadOutcome_AdoptedButUnobservedCopyWith(BridgeConfigurationReloadOutcome_AdoptedButUnobserved value, $Res Function(BridgeConfigurationReloadOutcome_AdoptedButUnobserved) _then) = _$BridgeConfigurationReloadOutcome_AdoptedButUnobservedCopyWithImpl;
@override @useResult
$Res call({
 String operationId, BridgeError error
});




}
/// @nodoc
class _$BridgeConfigurationReloadOutcome_AdoptedButUnobservedCopyWithImpl<$Res>
    implements $BridgeConfigurationReloadOutcome_AdoptedButUnobservedCopyWith<$Res> {
  _$BridgeConfigurationReloadOutcome_AdoptedButUnobservedCopyWithImpl(this._self, this._then);

  final BridgeConfigurationReloadOutcome_AdoptedButUnobserved _self;
  final $Res Function(BridgeConfigurationReloadOutcome_AdoptedButUnobserved) _then;

/// Create a copy of BridgeConfigurationReloadOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? error = null,}) {
  return _then(BridgeConfigurationReloadOutcome_AdoptedButUnobserved(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeConfigurationReloadOutcome_Rejected extends BridgeConfigurationReloadOutcome {
  const BridgeConfigurationReloadOutcome_Rejected({required this.operationId, required this.error}): super._();


@override final  String operationId;
 final  BridgeError error;

/// Create a copy of BridgeConfigurationReloadOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationReloadOutcome_RejectedCopyWith<BridgeConfigurationReloadOutcome_Rejected> get copyWith => _$BridgeConfigurationReloadOutcome_RejectedCopyWithImpl<BridgeConfigurationReloadOutcome_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationReloadOutcome_Rejected&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,error);
}

@override
String toString() {
    return 'BridgeConfigurationReloadOutcome.rejected(operationId: $operationId, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationReloadOutcome_RejectedCopyWith<$Res> implements $BridgeConfigurationReloadOutcomeCopyWith<$Res> {
  factory $BridgeConfigurationReloadOutcome_RejectedCopyWith(BridgeConfigurationReloadOutcome_Rejected value, $Res Function(BridgeConfigurationReloadOutcome_Rejected) _then) = _$BridgeConfigurationReloadOutcome_RejectedCopyWithImpl;
@override @useResult
$Res call({
 String operationId, BridgeError error
});




}
/// @nodoc
class _$BridgeConfigurationReloadOutcome_RejectedCopyWithImpl<$Res>
    implements $BridgeConfigurationReloadOutcome_RejectedCopyWith<$Res> {
  _$BridgeConfigurationReloadOutcome_RejectedCopyWithImpl(this._self, this._then);

  final BridgeConfigurationReloadOutcome_Rejected _self;
  final $Res Function(BridgeConfigurationReloadOutcome_Rejected) _then;

/// Create a copy of BridgeConfigurationReloadOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? error = null,}) {
  return _then(BridgeConfigurationReloadOutcome_Rejected(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeConfigurationReloadOutcome_Unknown extends BridgeConfigurationReloadOutcome {
  const BridgeConfigurationReloadOutcome_Unknown({required this.operationId, required this.error}): super._();


@override final  String operationId;
 final  BridgeError error;

/// Create a copy of BridgeConfigurationReloadOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigurationReloadOutcome_UnknownCopyWith<BridgeConfigurationReloadOutcome_Unknown> get copyWith => _$BridgeConfigurationReloadOutcome_UnknownCopyWithImpl<BridgeConfigurationReloadOutcome_Unknown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfigurationReloadOutcome_Unknown&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,error);
}

@override
String toString() {
    return 'BridgeConfigurationReloadOutcome.unknown(operationId: $operationId, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigurationReloadOutcome_UnknownCopyWith<$Res> implements $BridgeConfigurationReloadOutcomeCopyWith<$Res> {
  factory $BridgeConfigurationReloadOutcome_UnknownCopyWith(BridgeConfigurationReloadOutcome_Unknown value, $Res Function(BridgeConfigurationReloadOutcome_Unknown) _then) = _$BridgeConfigurationReloadOutcome_UnknownCopyWithImpl;
@override @useResult
$Res call({
 String operationId, BridgeError error
});




}
/// @nodoc
class _$BridgeConfigurationReloadOutcome_UnknownCopyWithImpl<$Res>
    implements $BridgeConfigurationReloadOutcome_UnknownCopyWith<$Res> {
  _$BridgeConfigurationReloadOutcome_UnknownCopyWithImpl(this._self, this._then);

  final BridgeConfigurationReloadOutcome_Unknown _self;
  final $Res Function(BridgeConfigurationReloadOutcome_Unknown) _then;

/// Create a copy of BridgeConfigurationReloadOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? error = null,}) {
  return _then(BridgeConfigurationReloadOutcome_Unknown(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc
mixin _$BridgeProfileCommandOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProfileCommandOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeProfileCommandOutcome()';
}


}

/// @nodoc
class $BridgeProfileCommandOutcomeCopyWith<$Res>  {
$BridgeProfileCommandOutcomeCopyWith(BridgeProfileCommandOutcome _, $Res Function(BridgeProfileCommandOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeProfileCommandOutcome].
extension BridgeProfileCommandOutcomePatterns on BridgeProfileCommandOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeProfileCommandOutcome_Committed value)?  committed,TResult Function( BridgeProfileCommandOutcome_CommittedButUnobserved value)?  committedButUnobserved,TResult Function( BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt value)?  confirmedWithoutUsableReceipt,TResult Function( BridgeProfileCommandOutcome_Rejected value)?  rejected,TResult Function( BridgeProfileCommandOutcome_Unknown value)?  unknown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeProfileCommandOutcome_Committed() when committed != null:
return committed(_that);case BridgeProfileCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that);case BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt() when confirmedWithoutUsableReceipt != null:
return confirmedWithoutUsableReceipt(_that);case BridgeProfileCommandOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeProfileCommandOutcome_Unknown() when unknown != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeProfileCommandOutcome_Committed value)  committed,required TResult Function( BridgeProfileCommandOutcome_CommittedButUnobserved value)  committedButUnobserved,required TResult Function( BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt value)  confirmedWithoutUsableReceipt,required TResult Function( BridgeProfileCommandOutcome_Rejected value)  rejected,required TResult Function( BridgeProfileCommandOutcome_Unknown value)  unknown,}){
final _that = this;
switch (_that) {
case BridgeProfileCommandOutcome_Committed():
return committed(_that);case BridgeProfileCommandOutcome_CommittedButUnobserved():
return committedButUnobserved(_that);case BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt():
return confirmedWithoutUsableReceipt(_that);case BridgeProfileCommandOutcome_Rejected():
return rejected(_that);case BridgeProfileCommandOutcome_Unknown():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeProfileCommandOutcome_Committed value)?  committed,TResult? Function( BridgeProfileCommandOutcome_CommittedButUnobserved value)?  committedButUnobserved,TResult? Function( BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt value)?  confirmedWithoutUsableReceipt,TResult? Function( BridgeProfileCommandOutcome_Rejected value)?  rejected,TResult? Function( BridgeProfileCommandOutcome_Unknown value)?  unknown,}){
final _that = this;
switch (_that) {
case BridgeProfileCommandOutcome_Committed() when committed != null:
return committed(_that);case BridgeProfileCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that);case BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt() when confirmedWithoutUsableReceipt != null:
return confirmedWithoutUsableReceipt(_that);case BridgeProfileCommandOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeProfileCommandOutcome_Unknown() when unknown != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProfileCommandReply reply)?  committed,TResult Function( BridgeStudioCommandReceipt receipt,  BridgeError error)?  committedButUnobserved,TResult Function( String operationId,  BridgeError error)?  confirmedWithoutUsableReceipt,TResult Function( String operationId,  BridgeError error)?  rejected,TResult Function( String operationId,  BridgeError error)?  unknown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeProfileCommandOutcome_Committed() when committed != null:
return committed(_that.reply);case BridgeProfileCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that.receipt,_that.error);case BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt() when confirmedWithoutUsableReceipt != null:
return confirmedWithoutUsableReceipt(_that.operationId,_that.error);case BridgeProfileCommandOutcome_Rejected() when rejected != null:
return rejected(_that.operationId,_that.error);case BridgeProfileCommandOutcome_Unknown() when unknown != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProfileCommandReply reply)  committed,required TResult Function( BridgeStudioCommandReceipt receipt,  BridgeError error)  committedButUnobserved,required TResult Function( String operationId,  BridgeError error)  confirmedWithoutUsableReceipt,required TResult Function( String operationId,  BridgeError error)  rejected,required TResult Function( String operationId,  BridgeError error)  unknown,}) {final _that = this;
switch (_that) {
case BridgeProfileCommandOutcome_Committed():
return committed(_that.reply);case BridgeProfileCommandOutcome_CommittedButUnobserved():
return committedButUnobserved(_that.receipt,_that.error);case BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt():
return confirmedWithoutUsableReceipt(_that.operationId,_that.error);case BridgeProfileCommandOutcome_Rejected():
return rejected(_that.operationId,_that.error);case BridgeProfileCommandOutcome_Unknown():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProfileCommandReply reply)?  committed,TResult? Function( BridgeStudioCommandReceipt receipt,  BridgeError error)?  committedButUnobserved,TResult? Function( String operationId,  BridgeError error)?  confirmedWithoutUsableReceipt,TResult? Function( String operationId,  BridgeError error)?  rejected,TResult? Function( String operationId,  BridgeError error)?  unknown,}) {final _that = this;
switch (_that) {
case BridgeProfileCommandOutcome_Committed() when committed != null:
return committed(_that.reply);case BridgeProfileCommandOutcome_CommittedButUnobserved() when committedButUnobserved != null:
return committedButUnobserved(_that.receipt,_that.error);case BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt() when confirmedWithoutUsableReceipt != null:
return confirmedWithoutUsableReceipt(_that.operationId,_that.error);case BridgeProfileCommandOutcome_Rejected() when rejected != null:
return rejected(_that.operationId,_that.error);case BridgeProfileCommandOutcome_Unknown() when unknown != null:
return unknown(_that.operationId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeProfileCommandOutcome_Committed extends BridgeProfileCommandOutcome {
  const BridgeProfileCommandOutcome_Committed({required this.reply}): super._();


 final  BridgeProfileCommandReply reply;

/// Create a copy of BridgeProfileCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProfileCommandOutcome_CommittedCopyWith<BridgeProfileCommandOutcome_Committed> get copyWith => _$BridgeProfileCommandOutcome_CommittedCopyWithImpl<BridgeProfileCommandOutcome_Committed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProfileCommandOutcome_Committed&&(identical(other.reply, reply) || other.reply == reply));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reply);
}

@override
String toString() {
    return 'BridgeProfileCommandOutcome.committed(reply: $reply)';
}


}

/// @nodoc
abstract mixin class $BridgeProfileCommandOutcome_CommittedCopyWith<$Res> implements $BridgeProfileCommandOutcomeCopyWith<$Res> {
  factory $BridgeProfileCommandOutcome_CommittedCopyWith(BridgeProfileCommandOutcome_Committed value, $Res Function(BridgeProfileCommandOutcome_Committed) _then) = _$BridgeProfileCommandOutcome_CommittedCopyWithImpl;
@useResult
$Res call({
 BridgeProfileCommandReply reply
});




}
/// @nodoc
class _$BridgeProfileCommandOutcome_CommittedCopyWithImpl<$Res>
    implements $BridgeProfileCommandOutcome_CommittedCopyWith<$Res> {
  _$BridgeProfileCommandOutcome_CommittedCopyWithImpl(this._self, this._then);

  final BridgeProfileCommandOutcome_Committed _self;
  final $Res Function(BridgeProfileCommandOutcome_Committed) _then;

/// Create a copy of BridgeProfileCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reply = null,}) {
  return _then(BridgeProfileCommandOutcome_Committed(
reply: null == reply ? _self.reply : reply // ignore: cast_nullable_to_non_nullable
as BridgeProfileCommandReply,
  ));
}


}

/// @nodoc


class BridgeProfileCommandOutcome_CommittedButUnobserved extends BridgeProfileCommandOutcome {
  const BridgeProfileCommandOutcome_CommittedButUnobserved({required this.receipt, required this.error}): super._();


 final  BridgeStudioCommandReceipt receipt;
 final  BridgeError error;

/// Create a copy of BridgeProfileCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProfileCommandOutcome_CommittedButUnobservedCopyWith<BridgeProfileCommandOutcome_CommittedButUnobserved> get copyWith => _$BridgeProfileCommandOutcome_CommittedButUnobservedCopyWithImpl<BridgeProfileCommandOutcome_CommittedButUnobserved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProfileCommandOutcome_CommittedButUnobserved&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receipt,error);
}

@override
String toString() {
    return 'BridgeProfileCommandOutcome.committedButUnobserved(receipt: $receipt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeProfileCommandOutcome_CommittedButUnobservedCopyWith<$Res> implements $BridgeProfileCommandOutcomeCopyWith<$Res> {
  factory $BridgeProfileCommandOutcome_CommittedButUnobservedCopyWith(BridgeProfileCommandOutcome_CommittedButUnobserved value, $Res Function(BridgeProfileCommandOutcome_CommittedButUnobserved) _then) = _$BridgeProfileCommandOutcome_CommittedButUnobservedCopyWithImpl;
@useResult
$Res call({
 BridgeStudioCommandReceipt receipt, BridgeError error
});




}
/// @nodoc
class _$BridgeProfileCommandOutcome_CommittedButUnobservedCopyWithImpl<$Res>
    implements $BridgeProfileCommandOutcome_CommittedButUnobservedCopyWith<$Res> {
  _$BridgeProfileCommandOutcome_CommittedButUnobservedCopyWithImpl(this._self, this._then);

  final BridgeProfileCommandOutcome_CommittedButUnobserved _self;
  final $Res Function(BridgeProfileCommandOutcome_CommittedButUnobserved) _then;

/// Create a copy of BridgeProfileCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? receipt = null,Object? error = null,}) {
  return _then(BridgeProfileCommandOutcome_CommittedButUnobserved(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as BridgeStudioCommandReceipt,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt extends BridgeProfileCommandOutcome {
  const BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt({required this.operationId, required this.error}): super._();


 final  String operationId;
 final  BridgeError error;

/// Create a copy of BridgeProfileCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceiptCopyWith<BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt> get copyWith => _$BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceiptCopyWithImpl<BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,error);
}

@override
String toString() {
    return 'BridgeProfileCommandOutcome.confirmedWithoutUsableReceipt(operationId: $operationId, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceiptCopyWith<$Res> implements $BridgeProfileCommandOutcomeCopyWith<$Res> {
  factory $BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceiptCopyWith(BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt value, $Res Function(BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt) _then) = _$BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceiptCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeError error
});




}
/// @nodoc
class _$BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceiptCopyWithImpl<$Res>
    implements $BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceiptCopyWith<$Res> {
  _$BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceiptCopyWithImpl(this._self, this._then);

  final BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt _self;
  final $Res Function(BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt) _then;

/// Create a copy of BridgeProfileCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? error = null,}) {
  return _then(BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeProfileCommandOutcome_Rejected extends BridgeProfileCommandOutcome {
  const BridgeProfileCommandOutcome_Rejected({required this.operationId, required this.error}): super._();


 final  String operationId;
 final  BridgeError error;

/// Create a copy of BridgeProfileCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProfileCommandOutcome_RejectedCopyWith<BridgeProfileCommandOutcome_Rejected> get copyWith => _$BridgeProfileCommandOutcome_RejectedCopyWithImpl<BridgeProfileCommandOutcome_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProfileCommandOutcome_Rejected&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,error);
}

@override
String toString() {
    return 'BridgeProfileCommandOutcome.rejected(operationId: $operationId, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeProfileCommandOutcome_RejectedCopyWith<$Res> implements $BridgeProfileCommandOutcomeCopyWith<$Res> {
  factory $BridgeProfileCommandOutcome_RejectedCopyWith(BridgeProfileCommandOutcome_Rejected value, $Res Function(BridgeProfileCommandOutcome_Rejected) _then) = _$BridgeProfileCommandOutcome_RejectedCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeError error
});




}
/// @nodoc
class _$BridgeProfileCommandOutcome_RejectedCopyWithImpl<$Res>
    implements $BridgeProfileCommandOutcome_RejectedCopyWith<$Res> {
  _$BridgeProfileCommandOutcome_RejectedCopyWithImpl(this._self, this._then);

  final BridgeProfileCommandOutcome_Rejected _self;
  final $Res Function(BridgeProfileCommandOutcome_Rejected) _then;

/// Create a copy of BridgeProfileCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? error = null,}) {
  return _then(BridgeProfileCommandOutcome_Rejected(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeProfileCommandOutcome_Unknown extends BridgeProfileCommandOutcome {
  const BridgeProfileCommandOutcome_Unknown({required this.operationId, required this.error}): super._();


 final  String operationId;
 final  BridgeError error;

/// Create a copy of BridgeProfileCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProfileCommandOutcome_UnknownCopyWith<BridgeProfileCommandOutcome_Unknown> get copyWith => _$BridgeProfileCommandOutcome_UnknownCopyWithImpl<BridgeProfileCommandOutcome_Unknown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProfileCommandOutcome_Unknown&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,error);
}

@override
String toString() {
    return 'BridgeProfileCommandOutcome.unknown(operationId: $operationId, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeProfileCommandOutcome_UnknownCopyWith<$Res> implements $BridgeProfileCommandOutcomeCopyWith<$Res> {
  factory $BridgeProfileCommandOutcome_UnknownCopyWith(BridgeProfileCommandOutcome_Unknown value, $Res Function(BridgeProfileCommandOutcome_Unknown) _then) = _$BridgeProfileCommandOutcome_UnknownCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeError error
});




}
/// @nodoc
class _$BridgeProfileCommandOutcome_UnknownCopyWithImpl<$Res>
    implements $BridgeProfileCommandOutcome_UnknownCopyWith<$Res> {
  _$BridgeProfileCommandOutcome_UnknownCopyWithImpl(this._self, this._then);

  final BridgeProfileCommandOutcome_Unknown _self;
  final $Res Function(BridgeProfileCommandOutcome_Unknown) _then;

/// Create a copy of BridgeProfileCommandOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? error = null,}) {
  return _then(BridgeProfileCommandOutcome_Unknown(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc
mixin _$BridgeProfileCommandRequest {

 Object get request;



@override
bool operator ==(Object other) {
  final _this = this as BridgeProfileCommandRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProfileCommandRequest&&const DeepCollectionEquality().equals(other.request, _this.request));
}


@override
int get hashCode {
  final _this = this as BridgeProfileCommandRequest;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.request));
}

@override
String toString() {
  final _this = this as BridgeProfileCommandRequest;
  return 'BridgeProfileCommandRequest(request: ${_this.request})';
}


}

/// @nodoc
class $BridgeProfileCommandRequestCopyWith<$Res>  {
$BridgeProfileCommandRequestCopyWith(BridgeProfileCommandRequest _, $Res Function(BridgeProfileCommandRequest) __);
}


/// Adds pattern-matching-related methods to [BridgeProfileCommandRequest].
extension BridgeProfileCommandRequestPatterns on BridgeProfileCommandRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeProfileCommandRequest_SaveProfile value)?  saveProfile,TResult Function( BridgeProfileCommandRequest_SetSystemProfileEnabled value)?  setSystemProfileEnabled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeProfileCommandRequest_SaveProfile() when saveProfile != null:
return saveProfile(_that);case BridgeProfileCommandRequest_SetSystemProfileEnabled() when setSystemProfileEnabled != null:
return setSystemProfileEnabled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeProfileCommandRequest_SaveProfile value)  saveProfile,required TResult Function( BridgeProfileCommandRequest_SetSystemProfileEnabled value)  setSystemProfileEnabled,}){
final _that = this;
switch (_that) {
case BridgeProfileCommandRequest_SaveProfile():
return saveProfile(_that);case BridgeProfileCommandRequest_SetSystemProfileEnabled():
return setSystemProfileEnabled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeProfileCommandRequest_SaveProfile value)?  saveProfile,TResult? Function( BridgeProfileCommandRequest_SetSystemProfileEnabled value)?  setSystemProfileEnabled,}){
final _that = this;
switch (_that) {
case BridgeProfileCommandRequest_SaveProfile() when saveProfile != null:
return saveProfile(_that);case BridgeProfileCommandRequest_SetSystemProfileEnabled() when setSystemProfileEnabled != null:
return setSystemProfileEnabled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeSaveProfileRequest request)?  saveProfile,TResult Function( BridgeSetSystemProfileEnabledRequest request)?  setSystemProfileEnabled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeProfileCommandRequest_SaveProfile() when saveProfile != null:
return saveProfile(_that.request);case BridgeProfileCommandRequest_SetSystemProfileEnabled() when setSystemProfileEnabled != null:
return setSystemProfileEnabled(_that.request);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeSaveProfileRequest request)  saveProfile,required TResult Function( BridgeSetSystemProfileEnabledRequest request)  setSystemProfileEnabled,}) {final _that = this;
switch (_that) {
case BridgeProfileCommandRequest_SaveProfile():
return saveProfile(_that.request);case BridgeProfileCommandRequest_SetSystemProfileEnabled():
return setSystemProfileEnabled(_that.request);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeSaveProfileRequest request)?  saveProfile,TResult? Function( BridgeSetSystemProfileEnabledRequest request)?  setSystemProfileEnabled,}) {final _that = this;
switch (_that) {
case BridgeProfileCommandRequest_SaveProfile() when saveProfile != null:
return saveProfile(_that.request);case BridgeProfileCommandRequest_SetSystemProfileEnabled() when setSystemProfileEnabled != null:
return setSystemProfileEnabled(_that.request);case _:
  return null;

}
}

}

/// @nodoc


class BridgeProfileCommandRequest_SaveProfile extends BridgeProfileCommandRequest {
  const BridgeProfileCommandRequest_SaveProfile({required this.request}): super._();


@override final  BridgeSaveProfileRequest request;

/// Create a copy of BridgeProfileCommandRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProfileCommandRequest_SaveProfileCopyWith<BridgeProfileCommandRequest_SaveProfile> get copyWith => _$BridgeProfileCommandRequest_SaveProfileCopyWithImpl<BridgeProfileCommandRequest_SaveProfile>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProfileCommandRequest_SaveProfile&&(identical(other.request, request) || other.request == request));
}


@override
int get hashCode {
    return Object.hash(runtimeType,request);
}

@override
String toString() {
    return 'BridgeProfileCommandRequest.saveProfile(request: $request)';
}


}

/// @nodoc
abstract mixin class $BridgeProfileCommandRequest_SaveProfileCopyWith<$Res> implements $BridgeProfileCommandRequestCopyWith<$Res> {
  factory $BridgeProfileCommandRequest_SaveProfileCopyWith(BridgeProfileCommandRequest_SaveProfile value, $Res Function(BridgeProfileCommandRequest_SaveProfile) _then) = _$BridgeProfileCommandRequest_SaveProfileCopyWithImpl;
@useResult
$Res call({
 BridgeSaveProfileRequest request
});




}
/// @nodoc
class _$BridgeProfileCommandRequest_SaveProfileCopyWithImpl<$Res>
    implements $BridgeProfileCommandRequest_SaveProfileCopyWith<$Res> {
  _$BridgeProfileCommandRequest_SaveProfileCopyWithImpl(this._self, this._then);

  final BridgeProfileCommandRequest_SaveProfile _self;
  final $Res Function(BridgeProfileCommandRequest_SaveProfile) _then;

/// Create a copy of BridgeProfileCommandRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? request = null,}) {
  return _then(BridgeProfileCommandRequest_SaveProfile(
request: null == request ? _self.request : request // ignore: cast_nullable_to_non_nullable
as BridgeSaveProfileRequest,
  ));
}


}

/// @nodoc


class BridgeProfileCommandRequest_SetSystemProfileEnabled extends BridgeProfileCommandRequest {
  const BridgeProfileCommandRequest_SetSystemProfileEnabled({required this.request}): super._();


@override final  BridgeSetSystemProfileEnabledRequest request;

/// Create a copy of BridgeProfileCommandRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProfileCommandRequest_SetSystemProfileEnabledCopyWith<BridgeProfileCommandRequest_SetSystemProfileEnabled> get copyWith => _$BridgeProfileCommandRequest_SetSystemProfileEnabledCopyWithImpl<BridgeProfileCommandRequest_SetSystemProfileEnabled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProfileCommandRequest_SetSystemProfileEnabled&&(identical(other.request, request) || other.request == request));
}


@override
int get hashCode {
    return Object.hash(runtimeType,request);
}

@override
String toString() {
    return 'BridgeProfileCommandRequest.setSystemProfileEnabled(request: $request)';
}


}

/// @nodoc
abstract mixin class $BridgeProfileCommandRequest_SetSystemProfileEnabledCopyWith<$Res> implements $BridgeProfileCommandRequestCopyWith<$Res> {
  factory $BridgeProfileCommandRequest_SetSystemProfileEnabledCopyWith(BridgeProfileCommandRequest_SetSystemProfileEnabled value, $Res Function(BridgeProfileCommandRequest_SetSystemProfileEnabled) _then) = _$BridgeProfileCommandRequest_SetSystemProfileEnabledCopyWithImpl;
@useResult
$Res call({
 BridgeSetSystemProfileEnabledRequest request
});




}
/// @nodoc
class _$BridgeProfileCommandRequest_SetSystemProfileEnabledCopyWithImpl<$Res>
    implements $BridgeProfileCommandRequest_SetSystemProfileEnabledCopyWith<$Res> {
  _$BridgeProfileCommandRequest_SetSystemProfileEnabledCopyWithImpl(this._self, this._then);

  final BridgeProfileCommandRequest_SetSystemProfileEnabled _self;
  final $Res Function(BridgeProfileCommandRequest_SetSystemProfileEnabled) _then;

/// Create a copy of BridgeProfileCommandRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? request = null,}) {
  return _then(BridgeProfileCommandRequest_SetSystemProfileEnabled(
request: null == request ? _self.request : request // ignore: cast_nullable_to_non_nullable
as BridgeSetSystemProfileEnabledRequest,
  ));
}


}

// dart format on
