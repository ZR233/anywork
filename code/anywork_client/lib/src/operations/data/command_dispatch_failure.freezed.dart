// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'command_dispatch_failure.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CommandDispatchFailure {

 StudioFailure get failure;
/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommandDispatchFailureCopyWith<CommandDispatchFailure> get copyWith => _$CommandDispatchFailureCopyWithImpl<CommandDispatchFailure>(this as CommandDispatchFailure, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CommandDispatchFailure;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandDispatchFailure&&(identical(other.failure, _this.failure) || other.failure == _this.failure));
}


@override
int get hashCode {
  final _this = this as CommandDispatchFailure;
  return Object.hash(runtimeType,_this.failure);
}



}

/// @nodoc
abstract mixin class $CommandDispatchFailureCopyWith<$Res>  {
  factory $CommandDispatchFailureCopyWith(CommandDispatchFailure value, $Res Function(CommandDispatchFailure) _then) = _$CommandDispatchFailureCopyWithImpl;
@useResult
$Res call({
 StudioFailure failure
});


$StudioFailureCopyWith<$Res> get failure;

}
/// @nodoc
class _$CommandDispatchFailureCopyWithImpl<$Res>
    implements $CommandDispatchFailureCopyWith<$Res> {
  _$CommandDispatchFailureCopyWithImpl(this._self, this._then);

  final CommandDispatchFailure _self;
  final $Res Function(CommandDispatchFailure) _then;

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? failure = null,}) {
  return _then(_self.copyWith(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}
/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get failure {

  return $StudioFailureCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}


/// Adds pattern-matching-related methods to [CommandDispatchFailure].
extension CommandDispatchFailurePatterns on CommandDispatchFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RejectedCommandDispatchFailure value)?  rejected,TResult Function( UnknownOutcomeCommandDispatchFailure value)?  unknownOutcome,TResult Function( CommittedButUnobservedCommandDispatchFailure value)?  committedButUnobserved,TResult Function( ConfirmedWithoutUsableReceiptCommandDispatchFailure value)?  confirmedWithoutUsableReceipt,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RejectedCommandDispatchFailure() when rejected != null:
return rejected(_that);case UnknownOutcomeCommandDispatchFailure() when unknownOutcome != null:
return unknownOutcome(_that);case CommittedButUnobservedCommandDispatchFailure() when committedButUnobserved != null:
return committedButUnobserved(_that);case ConfirmedWithoutUsableReceiptCommandDispatchFailure() when confirmedWithoutUsableReceipt != null:
return confirmedWithoutUsableReceipt(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RejectedCommandDispatchFailure value)  rejected,required TResult Function( UnknownOutcomeCommandDispatchFailure value)  unknownOutcome,required TResult Function( CommittedButUnobservedCommandDispatchFailure value)  committedButUnobserved,required TResult Function( ConfirmedWithoutUsableReceiptCommandDispatchFailure value)  confirmedWithoutUsableReceipt,}){
final _that = this;
switch (_that) {
case RejectedCommandDispatchFailure():
return rejected(_that);case UnknownOutcomeCommandDispatchFailure():
return unknownOutcome(_that);case CommittedButUnobservedCommandDispatchFailure():
return committedButUnobserved(_that);case ConfirmedWithoutUsableReceiptCommandDispatchFailure():
return confirmedWithoutUsableReceipt(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RejectedCommandDispatchFailure value)?  rejected,TResult? Function( UnknownOutcomeCommandDispatchFailure value)?  unknownOutcome,TResult? Function( CommittedButUnobservedCommandDispatchFailure value)?  committedButUnobserved,TResult? Function( ConfirmedWithoutUsableReceiptCommandDispatchFailure value)?  confirmedWithoutUsableReceipt,}){
final _that = this;
switch (_that) {
case RejectedCommandDispatchFailure() when rejected != null:
return rejected(_that);case UnknownOutcomeCommandDispatchFailure() when unknownOutcome != null:
return unknownOutcome(_that);case CommittedButUnobservedCommandDispatchFailure() when committedButUnobserved != null:
return committedButUnobserved(_that);case ConfirmedWithoutUsableReceiptCommandDispatchFailure() when confirmedWithoutUsableReceipt != null:
return confirmedWithoutUsableReceipt(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( StudioFailure failure)?  rejected,TResult Function( StudioFailure failure)?  unknownOutcome,TResult Function( CommitReceipt receipt,  StudioFailure failure)?  committedButUnobserved,TResult Function( StudioFailure failure)?  confirmedWithoutUsableReceipt,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RejectedCommandDispatchFailure() when rejected != null:
return rejected(_that.failure);case UnknownOutcomeCommandDispatchFailure() when unknownOutcome != null:
return unknownOutcome(_that.failure);case CommittedButUnobservedCommandDispatchFailure() when committedButUnobserved != null:
return committedButUnobserved(_that.receipt,_that.failure);case ConfirmedWithoutUsableReceiptCommandDispatchFailure() when confirmedWithoutUsableReceipt != null:
return confirmedWithoutUsableReceipt(_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( StudioFailure failure)  rejected,required TResult Function( StudioFailure failure)  unknownOutcome,required TResult Function( CommitReceipt receipt,  StudioFailure failure)  committedButUnobserved,required TResult Function( StudioFailure failure)  confirmedWithoutUsableReceipt,}) {final _that = this;
switch (_that) {
case RejectedCommandDispatchFailure():
return rejected(_that.failure);case UnknownOutcomeCommandDispatchFailure():
return unknownOutcome(_that.failure);case CommittedButUnobservedCommandDispatchFailure():
return committedButUnobserved(_that.receipt,_that.failure);case ConfirmedWithoutUsableReceiptCommandDispatchFailure():
return confirmedWithoutUsableReceipt(_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( StudioFailure failure)?  rejected,TResult? Function( StudioFailure failure)?  unknownOutcome,TResult? Function( CommitReceipt receipt,  StudioFailure failure)?  committedButUnobserved,TResult? Function( StudioFailure failure)?  confirmedWithoutUsableReceipt,}) {final _that = this;
switch (_that) {
case RejectedCommandDispatchFailure() when rejected != null:
return rejected(_that.failure);case UnknownOutcomeCommandDispatchFailure() when unknownOutcome != null:
return unknownOutcome(_that.failure);case CommittedButUnobservedCommandDispatchFailure() when committedButUnobserved != null:
return committedButUnobserved(_that.receipt,_that.failure);case ConfirmedWithoutUsableReceiptCommandDispatchFailure() when confirmedWithoutUsableReceipt != null:
return confirmedWithoutUsableReceipt(_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class RejectedCommandDispatchFailure implements CommandDispatchFailure {
  const RejectedCommandDispatchFailure({required this.failure});


@override final  StudioFailure failure;

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RejectedCommandDispatchFailureCopyWith<RejectedCommandDispatchFailure> get copyWith => _$RejectedCommandDispatchFailureCopyWithImpl<RejectedCommandDispatchFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RejectedCommandDispatchFailure&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failure);
}



}

/// @nodoc
abstract mixin class $RejectedCommandDispatchFailureCopyWith<$Res> implements $CommandDispatchFailureCopyWith<$Res> {
  factory $RejectedCommandDispatchFailureCopyWith(RejectedCommandDispatchFailure value, $Res Function(RejectedCommandDispatchFailure) _then) = _$RejectedCommandDispatchFailureCopyWithImpl;
@override @useResult
$Res call({
 StudioFailure failure
});


@override $StudioFailureCopyWith<$Res> get failure;

}
/// @nodoc
class _$RejectedCommandDispatchFailureCopyWithImpl<$Res>
    implements $RejectedCommandDispatchFailureCopyWith<$Res> {
  _$RejectedCommandDispatchFailureCopyWithImpl(this._self, this._then);

  final RejectedCommandDispatchFailure _self;
  final $Res Function(RejectedCommandDispatchFailure) _then;

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(RejectedCommandDispatchFailure(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get failure {

  return $StudioFailureCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

/// @nodoc


class UnknownOutcomeCommandDispatchFailure implements CommandDispatchFailure {
  const UnknownOutcomeCommandDispatchFailure({required this.failure});


@override final  StudioFailure failure;

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnknownOutcomeCommandDispatchFailureCopyWith<UnknownOutcomeCommandDispatchFailure> get copyWith => _$UnknownOutcomeCommandDispatchFailureCopyWithImpl<UnknownOutcomeCommandDispatchFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnknownOutcomeCommandDispatchFailure&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failure);
}



}

/// @nodoc
abstract mixin class $UnknownOutcomeCommandDispatchFailureCopyWith<$Res> implements $CommandDispatchFailureCopyWith<$Res> {
  factory $UnknownOutcomeCommandDispatchFailureCopyWith(UnknownOutcomeCommandDispatchFailure value, $Res Function(UnknownOutcomeCommandDispatchFailure) _then) = _$UnknownOutcomeCommandDispatchFailureCopyWithImpl;
@override @useResult
$Res call({
 StudioFailure failure
});


@override $StudioFailureCopyWith<$Res> get failure;

}
/// @nodoc
class _$UnknownOutcomeCommandDispatchFailureCopyWithImpl<$Res>
    implements $UnknownOutcomeCommandDispatchFailureCopyWith<$Res> {
  _$UnknownOutcomeCommandDispatchFailureCopyWithImpl(this._self, this._then);

  final UnknownOutcomeCommandDispatchFailure _self;
  final $Res Function(UnknownOutcomeCommandDispatchFailure) _then;

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(UnknownOutcomeCommandDispatchFailure(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get failure {

  return $StudioFailureCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

/// @nodoc


class CommittedButUnobservedCommandDispatchFailure implements CommandDispatchFailure {
  const CommittedButUnobservedCommandDispatchFailure({required this.receipt, required this.failure});


 final  CommitReceipt receipt;
@override final  StudioFailure failure;

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommittedButUnobservedCommandDispatchFailureCopyWith<CommittedButUnobservedCommandDispatchFailure> get copyWith => _$CommittedButUnobservedCommandDispatchFailureCopyWithImpl<CommittedButUnobservedCommandDispatchFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CommittedButUnobservedCommandDispatchFailure&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receipt,failure);
}



}

/// @nodoc
abstract mixin class $CommittedButUnobservedCommandDispatchFailureCopyWith<$Res> implements $CommandDispatchFailureCopyWith<$Res> {
  factory $CommittedButUnobservedCommandDispatchFailureCopyWith(CommittedButUnobservedCommandDispatchFailure value, $Res Function(CommittedButUnobservedCommandDispatchFailure) _then) = _$CommittedButUnobservedCommandDispatchFailureCopyWithImpl;
@override @useResult
$Res call({
 CommitReceipt receipt, StudioFailure failure
});


$CommitReceiptCopyWith<$Res> get receipt;@override $StudioFailureCopyWith<$Res> get failure;

}
/// @nodoc
class _$CommittedButUnobservedCommandDispatchFailureCopyWithImpl<$Res>
    implements $CommittedButUnobservedCommandDispatchFailureCopyWith<$Res> {
  _$CommittedButUnobservedCommandDispatchFailureCopyWithImpl(this._self, this._then);

  final CommittedButUnobservedCommandDispatchFailure _self;
  final $Res Function(CommittedButUnobservedCommandDispatchFailure) _then;

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? receipt = null,Object? failure = null,}) {
  return _then(CommittedButUnobservedCommandDispatchFailure(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get failure {

  return $StudioFailureCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

/// @nodoc


class ConfirmedWithoutUsableReceiptCommandDispatchFailure implements CommandDispatchFailure {
  const ConfirmedWithoutUsableReceiptCommandDispatchFailure({required this.failure});


@override final  StudioFailure failure;

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfirmedWithoutUsableReceiptCommandDispatchFailureCopyWith<ConfirmedWithoutUsableReceiptCommandDispatchFailure> get copyWith => _$ConfirmedWithoutUsableReceiptCommandDispatchFailureCopyWithImpl<ConfirmedWithoutUsableReceiptCommandDispatchFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfirmedWithoutUsableReceiptCommandDispatchFailure&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failure);
}



}

/// @nodoc
abstract mixin class $ConfirmedWithoutUsableReceiptCommandDispatchFailureCopyWith<$Res> implements $CommandDispatchFailureCopyWith<$Res> {
  factory $ConfirmedWithoutUsableReceiptCommandDispatchFailureCopyWith(ConfirmedWithoutUsableReceiptCommandDispatchFailure value, $Res Function(ConfirmedWithoutUsableReceiptCommandDispatchFailure) _then) = _$ConfirmedWithoutUsableReceiptCommandDispatchFailureCopyWithImpl;
@override @useResult
$Res call({
 StudioFailure failure
});


@override $StudioFailureCopyWith<$Res> get failure;

}
/// @nodoc
class _$ConfirmedWithoutUsableReceiptCommandDispatchFailureCopyWithImpl<$Res>
    implements $ConfirmedWithoutUsableReceiptCommandDispatchFailureCopyWith<$Res> {
  _$ConfirmedWithoutUsableReceiptCommandDispatchFailureCopyWithImpl(this._self, this._then);

  final ConfirmedWithoutUsableReceiptCommandDispatchFailure _self;
  final $Res Function(ConfirmedWithoutUsableReceiptCommandDispatchFailure) _then;

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(ConfirmedWithoutUsableReceiptCommandDispatchFailure(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of CommandDispatchFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get failure {

  return $StudioFailureCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

// dart format on
