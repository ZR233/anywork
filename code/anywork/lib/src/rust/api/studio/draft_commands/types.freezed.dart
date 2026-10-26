// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAttachmentAdmissionOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAttachmentAdmissionOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAttachmentAdmissionOutcome()';
}


}

/// @nodoc
class $BridgeAttachmentAdmissionOutcomeCopyWith<$Res>  {
$BridgeAttachmentAdmissionOutcomeCopyWith(BridgeAttachmentAdmissionOutcome _, $Res Function(BridgeAttachmentAdmissionOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeAttachmentAdmissionOutcome].
extension BridgeAttachmentAdmissionOutcomePatterns on BridgeAttachmentAdmissionOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAttachmentAdmissionOutcome_Returned value)?  returned,TResult Function( BridgeAttachmentAdmissionOutcome_Rejected value)?  rejected,TResult Function( BridgeAttachmentAdmissionOutcome_UnknownOutcome value)?  unknownOutcome,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAttachmentAdmissionOutcome_Returned() when returned != null:
return returned(_that);case BridgeAttachmentAdmissionOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeAttachmentAdmissionOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAttachmentAdmissionOutcome_Returned value)  returned,required TResult Function( BridgeAttachmentAdmissionOutcome_Rejected value)  rejected,required TResult Function( BridgeAttachmentAdmissionOutcome_UnknownOutcome value)  unknownOutcome,}){
final _that = this;
switch (_that) {
case BridgeAttachmentAdmissionOutcome_Returned():
return returned(_that);case BridgeAttachmentAdmissionOutcome_Rejected():
return rejected(_that);case BridgeAttachmentAdmissionOutcome_UnknownOutcome():
return unknownOutcome(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAttachmentAdmissionOutcome_Returned value)?  returned,TResult? Function( BridgeAttachmentAdmissionOutcome_Rejected value)?  rejected,TResult? Function( BridgeAttachmentAdmissionOutcome_UnknownOutcome value)?  unknownOutcome,}){
final _that = this;
switch (_that) {
case BridgeAttachmentAdmissionOutcome_Returned() when returned != null:
return returned(_that);case BridgeAttachmentAdmissionOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeAttachmentAdmissionOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<BridgeAttachmentDraft> drafts)?  returned,TResult Function( BridgeError error)?  rejected,TResult Function( BridgeError error)?  unknownOutcome,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAttachmentAdmissionOutcome_Returned() when returned != null:
return returned(_that.drafts);case BridgeAttachmentAdmissionOutcome_Rejected() when rejected != null:
return rejected(_that.error);case BridgeAttachmentAdmissionOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<BridgeAttachmentDraft> drafts)  returned,required TResult Function( BridgeError error)  rejected,required TResult Function( BridgeError error)  unknownOutcome,}) {final _that = this;
switch (_that) {
case BridgeAttachmentAdmissionOutcome_Returned():
return returned(_that.drafts);case BridgeAttachmentAdmissionOutcome_Rejected():
return rejected(_that.error);case BridgeAttachmentAdmissionOutcome_UnknownOutcome():
return unknownOutcome(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<BridgeAttachmentDraft> drafts)?  returned,TResult? Function( BridgeError error)?  rejected,TResult? Function( BridgeError error)?  unknownOutcome,}) {final _that = this;
switch (_that) {
case BridgeAttachmentAdmissionOutcome_Returned() when returned != null:
return returned(_that.drafts);case BridgeAttachmentAdmissionOutcome_Rejected() when rejected != null:
return rejected(_that.error);case BridgeAttachmentAdmissionOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAttachmentAdmissionOutcome_Returned extends BridgeAttachmentAdmissionOutcome {
  const BridgeAttachmentAdmissionOutcome_Returned({required  List<BridgeAttachmentDraft> drafts}): _drafts = drafts,super._();


 final  List<BridgeAttachmentDraft> _drafts;
 List<BridgeAttachmentDraft> get drafts {
  if (_drafts is EqualUnmodifiableListView) return _drafts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_drafts);
}


/// Create a copy of BridgeAttachmentAdmissionOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAttachmentAdmissionOutcome_ReturnedCopyWith<BridgeAttachmentAdmissionOutcome_Returned> get copyWith => _$BridgeAttachmentAdmissionOutcome_ReturnedCopyWithImpl<BridgeAttachmentAdmissionOutcome_Returned>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAttachmentAdmissionOutcome_Returned&&const DeepCollectionEquality().equals(other.drafts, _drafts));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_drafts));
}

@override
String toString() {
    return 'BridgeAttachmentAdmissionOutcome.returned(drafts: $drafts)';
}


}

/// @nodoc
abstract mixin class $BridgeAttachmentAdmissionOutcome_ReturnedCopyWith<$Res> implements $BridgeAttachmentAdmissionOutcomeCopyWith<$Res> {
  factory $BridgeAttachmentAdmissionOutcome_ReturnedCopyWith(BridgeAttachmentAdmissionOutcome_Returned value, $Res Function(BridgeAttachmentAdmissionOutcome_Returned) _then) = _$BridgeAttachmentAdmissionOutcome_ReturnedCopyWithImpl;
@useResult
$Res call({
 List<BridgeAttachmentDraft> drafts
});




}
/// @nodoc
class _$BridgeAttachmentAdmissionOutcome_ReturnedCopyWithImpl<$Res>
    implements $BridgeAttachmentAdmissionOutcome_ReturnedCopyWith<$Res> {
  _$BridgeAttachmentAdmissionOutcome_ReturnedCopyWithImpl(this._self, this._then);

  final BridgeAttachmentAdmissionOutcome_Returned _self;
  final $Res Function(BridgeAttachmentAdmissionOutcome_Returned) _then;

/// Create a copy of BridgeAttachmentAdmissionOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? drafts = null,}) {
  return _then(BridgeAttachmentAdmissionOutcome_Returned(
drafts: null == drafts ? _self._drafts : drafts // ignore: cast_nullable_to_non_nullable
as List<BridgeAttachmentDraft>,
  ));
}


}

/// @nodoc


class BridgeAttachmentAdmissionOutcome_Rejected extends BridgeAttachmentAdmissionOutcome {
  const BridgeAttachmentAdmissionOutcome_Rejected({required this.error}): super._();


 final  BridgeError error;

/// Create a copy of BridgeAttachmentAdmissionOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAttachmentAdmissionOutcome_RejectedCopyWith<BridgeAttachmentAdmissionOutcome_Rejected> get copyWith => _$BridgeAttachmentAdmissionOutcome_RejectedCopyWithImpl<BridgeAttachmentAdmissionOutcome_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAttachmentAdmissionOutcome_Rejected&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeAttachmentAdmissionOutcome.rejected(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAttachmentAdmissionOutcome_RejectedCopyWith<$Res> implements $BridgeAttachmentAdmissionOutcomeCopyWith<$Res> {
  factory $BridgeAttachmentAdmissionOutcome_RejectedCopyWith(BridgeAttachmentAdmissionOutcome_Rejected value, $Res Function(BridgeAttachmentAdmissionOutcome_Rejected) _then) = _$BridgeAttachmentAdmissionOutcome_RejectedCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeAttachmentAdmissionOutcome_RejectedCopyWithImpl<$Res>
    implements $BridgeAttachmentAdmissionOutcome_RejectedCopyWith<$Res> {
  _$BridgeAttachmentAdmissionOutcome_RejectedCopyWithImpl(this._self, this._then);

  final BridgeAttachmentAdmissionOutcome_Rejected _self;
  final $Res Function(BridgeAttachmentAdmissionOutcome_Rejected) _then;

/// Create a copy of BridgeAttachmentAdmissionOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeAttachmentAdmissionOutcome_Rejected(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeAttachmentAdmissionOutcome_UnknownOutcome extends BridgeAttachmentAdmissionOutcome {
  const BridgeAttachmentAdmissionOutcome_UnknownOutcome({required this.error}): super._();


 final  BridgeError error;

/// Create a copy of BridgeAttachmentAdmissionOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAttachmentAdmissionOutcome_UnknownOutcomeCopyWith<BridgeAttachmentAdmissionOutcome_UnknownOutcome> get copyWith => _$BridgeAttachmentAdmissionOutcome_UnknownOutcomeCopyWithImpl<BridgeAttachmentAdmissionOutcome_UnknownOutcome>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAttachmentAdmissionOutcome_UnknownOutcome&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeAttachmentAdmissionOutcome.unknownOutcome(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAttachmentAdmissionOutcome_UnknownOutcomeCopyWith<$Res> implements $BridgeAttachmentAdmissionOutcomeCopyWith<$Res> {
  factory $BridgeAttachmentAdmissionOutcome_UnknownOutcomeCopyWith(BridgeAttachmentAdmissionOutcome_UnknownOutcome value, $Res Function(BridgeAttachmentAdmissionOutcome_UnknownOutcome) _then) = _$BridgeAttachmentAdmissionOutcome_UnknownOutcomeCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeAttachmentAdmissionOutcome_UnknownOutcomeCopyWithImpl<$Res>
    implements $BridgeAttachmentAdmissionOutcome_UnknownOutcomeCopyWith<$Res> {
  _$BridgeAttachmentAdmissionOutcome_UnknownOutcomeCopyWithImpl(this._self, this._then);

  final BridgeAttachmentAdmissionOutcome_UnknownOutcome _self;
  final $Res Function(BridgeAttachmentAdmissionOutcome_UnknownOutcome) _then;

/// Create a copy of BridgeAttachmentAdmissionOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeAttachmentAdmissionOutcome_UnknownOutcome(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc
mixin _$BridgeDraftCommandBeginFailure {

 BridgeError get error;
/// Create a copy of BridgeDraftCommandBeginFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeDraftCommandBeginFailureCopyWith<BridgeDraftCommandBeginFailure> get copyWith => _$BridgeDraftCommandBeginFailureCopyWithImpl<BridgeDraftCommandBeginFailure>(this as BridgeDraftCommandBeginFailure, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeDraftCommandBeginFailure;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDraftCommandBeginFailure&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as BridgeDraftCommandBeginFailure;
  return Object.hash(runtimeType,_this.error);
}

@override
String toString() {
  final _this = this as BridgeDraftCommandBeginFailure;
  return 'BridgeDraftCommandBeginFailure(error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $BridgeDraftCommandBeginFailureCopyWith<$Res>  {
  factory $BridgeDraftCommandBeginFailureCopyWith(BridgeDraftCommandBeginFailure value, $Res Function(BridgeDraftCommandBeginFailure) _then) = _$BridgeDraftCommandBeginFailureCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeDraftCommandBeginFailureCopyWithImpl<$Res>
    implements $BridgeDraftCommandBeginFailureCopyWith<$Res> {
  _$BridgeDraftCommandBeginFailureCopyWithImpl(this._self, this._then);

  final BridgeDraftCommandBeginFailure _self;
  final $Res Function(BridgeDraftCommandBeginFailure) _then;

/// Create a copy of BridgeDraftCommandBeginFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? error = null,}) {
  return _then(_self.copyWith(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeDraftCommandBeginFailure].
extension BridgeDraftCommandBeginFailurePatterns on BridgeDraftCommandBeginFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeDraftCommandBeginFailure_Rejected value)?  rejected,TResult Function( BridgeDraftCommandBeginFailure_UnknownOutcome value)?  unknownOutcome,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeDraftCommandBeginFailure_Rejected() when rejected != null:
return rejected(_that);case BridgeDraftCommandBeginFailure_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeDraftCommandBeginFailure_Rejected value)  rejected,required TResult Function( BridgeDraftCommandBeginFailure_UnknownOutcome value)  unknownOutcome,}){
final _that = this;
switch (_that) {
case BridgeDraftCommandBeginFailure_Rejected():
return rejected(_that);case BridgeDraftCommandBeginFailure_UnknownOutcome():
return unknownOutcome(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeDraftCommandBeginFailure_Rejected value)?  rejected,TResult? Function( BridgeDraftCommandBeginFailure_UnknownOutcome value)?  unknownOutcome,}){
final _that = this;
switch (_that) {
case BridgeDraftCommandBeginFailure_Rejected() when rejected != null:
return rejected(_that);case BridgeDraftCommandBeginFailure_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeError error)?  rejected,TResult Function( BridgeError error)?  unknownOutcome,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeDraftCommandBeginFailure_Rejected() when rejected != null:
return rejected(_that.error);case BridgeDraftCommandBeginFailure_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeError error)  rejected,required TResult Function( BridgeError error)  unknownOutcome,}) {final _that = this;
switch (_that) {
case BridgeDraftCommandBeginFailure_Rejected():
return rejected(_that.error);case BridgeDraftCommandBeginFailure_UnknownOutcome():
return unknownOutcome(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeError error)?  rejected,TResult? Function( BridgeError error)?  unknownOutcome,}) {final _that = this;
switch (_that) {
case BridgeDraftCommandBeginFailure_Rejected() when rejected != null:
return rejected(_that.error);case BridgeDraftCommandBeginFailure_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeDraftCommandBeginFailure_Rejected extends BridgeDraftCommandBeginFailure {
  const BridgeDraftCommandBeginFailure_Rejected({required this.error}): super._();


@override final  BridgeError error;

/// Create a copy of BridgeDraftCommandBeginFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeDraftCommandBeginFailure_RejectedCopyWith<BridgeDraftCommandBeginFailure_Rejected> get copyWith => _$BridgeDraftCommandBeginFailure_RejectedCopyWithImpl<BridgeDraftCommandBeginFailure_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDraftCommandBeginFailure_Rejected&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeDraftCommandBeginFailure.rejected(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeDraftCommandBeginFailure_RejectedCopyWith<$Res> implements $BridgeDraftCommandBeginFailureCopyWith<$Res> {
  factory $BridgeDraftCommandBeginFailure_RejectedCopyWith(BridgeDraftCommandBeginFailure_Rejected value, $Res Function(BridgeDraftCommandBeginFailure_Rejected) _then) = _$BridgeDraftCommandBeginFailure_RejectedCopyWithImpl;
@override @useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeDraftCommandBeginFailure_RejectedCopyWithImpl<$Res>
    implements $BridgeDraftCommandBeginFailure_RejectedCopyWith<$Res> {
  _$BridgeDraftCommandBeginFailure_RejectedCopyWithImpl(this._self, this._then);

  final BridgeDraftCommandBeginFailure_Rejected _self;
  final $Res Function(BridgeDraftCommandBeginFailure_Rejected) _then;

/// Create a copy of BridgeDraftCommandBeginFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeDraftCommandBeginFailure_Rejected(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeDraftCommandBeginFailure_UnknownOutcome extends BridgeDraftCommandBeginFailure {
  const BridgeDraftCommandBeginFailure_UnknownOutcome({required this.error}): super._();


@override final  BridgeError error;

/// Create a copy of BridgeDraftCommandBeginFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeDraftCommandBeginFailure_UnknownOutcomeCopyWith<BridgeDraftCommandBeginFailure_UnknownOutcome> get copyWith => _$BridgeDraftCommandBeginFailure_UnknownOutcomeCopyWithImpl<BridgeDraftCommandBeginFailure_UnknownOutcome>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeDraftCommandBeginFailure_UnknownOutcome&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeDraftCommandBeginFailure.unknownOutcome(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeDraftCommandBeginFailure_UnknownOutcomeCopyWith<$Res> implements $BridgeDraftCommandBeginFailureCopyWith<$Res> {
  factory $BridgeDraftCommandBeginFailure_UnknownOutcomeCopyWith(BridgeDraftCommandBeginFailure_UnknownOutcome value, $Res Function(BridgeDraftCommandBeginFailure_UnknownOutcome) _then) = _$BridgeDraftCommandBeginFailure_UnknownOutcomeCopyWithImpl;
@override @useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeDraftCommandBeginFailure_UnknownOutcomeCopyWithImpl<$Res>
    implements $BridgeDraftCommandBeginFailure_UnknownOutcomeCopyWith<$Res> {
  _$BridgeDraftCommandBeginFailure_UnknownOutcomeCopyWithImpl(this._self, this._then);

  final BridgeDraftCommandBeginFailure_UnknownOutcome _self;
  final $Res Function(BridgeDraftCommandBeginFailure_UnknownOutcome) _then;

/// Create a copy of BridgeDraftCommandBeginFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeDraftCommandBeginFailure_UnknownOutcome(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc
mixin _$BridgeThreadCreationOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadCreationOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadCreationOutcome()';
}


}

/// @nodoc
class $BridgeThreadCreationOutcomeCopyWith<$Res>  {
$BridgeThreadCreationOutcomeCopyWith(BridgeThreadCreationOutcome _, $Res Function(BridgeThreadCreationOutcome) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadCreationOutcome].
extension BridgeThreadCreationOutcomePatterns on BridgeThreadCreationOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadCreationOutcome_Returned value)?  returned,TResult Function( BridgeThreadCreationOutcome_Rejected value)?  rejected,TResult Function( BridgeThreadCreationOutcome_UnknownOutcome value)?  unknownOutcome,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadCreationOutcome_Returned() when returned != null:
return returned(_that);case BridgeThreadCreationOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeThreadCreationOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadCreationOutcome_Returned value)  returned,required TResult Function( BridgeThreadCreationOutcome_Rejected value)  rejected,required TResult Function( BridgeThreadCreationOutcome_UnknownOutcome value)  unknownOutcome,}){
final _that = this;
switch (_that) {
case BridgeThreadCreationOutcome_Returned():
return returned(_that);case BridgeThreadCreationOutcome_Rejected():
return rejected(_that);case BridgeThreadCreationOutcome_UnknownOutcome():
return unknownOutcome(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadCreationOutcome_Returned value)?  returned,TResult? Function( BridgeThreadCreationOutcome_Rejected value)?  rejected,TResult? Function( BridgeThreadCreationOutcome_UnknownOutcome value)?  unknownOutcome,}){
final _that = this;
switch (_that) {
case BridgeThreadCreationOutcome_Returned() when returned != null:
return returned(_that);case BridgeThreadCreationOutcome_Rejected() when rejected != null:
return rejected(_that);case BridgeThreadCreationOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( StartNewThreadResponse value)?  returned,TResult Function( BridgeError error)?  rejected,TResult Function( BridgeError error)?  unknownOutcome,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadCreationOutcome_Returned() when returned != null:
return returned(_that.value);case BridgeThreadCreationOutcome_Rejected() when rejected != null:
return rejected(_that.error);case BridgeThreadCreationOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( StartNewThreadResponse value)  returned,required TResult Function( BridgeError error)  rejected,required TResult Function( BridgeError error)  unknownOutcome,}) {final _that = this;
switch (_that) {
case BridgeThreadCreationOutcome_Returned():
return returned(_that.value);case BridgeThreadCreationOutcome_Rejected():
return rejected(_that.error);case BridgeThreadCreationOutcome_UnknownOutcome():
return unknownOutcome(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( StartNewThreadResponse value)?  returned,TResult? Function( BridgeError error)?  rejected,TResult? Function( BridgeError error)?  unknownOutcome,}) {final _that = this;
switch (_that) {
case BridgeThreadCreationOutcome_Returned() when returned != null:
return returned(_that.value);case BridgeThreadCreationOutcome_Rejected() when rejected != null:
return rejected(_that.error);case BridgeThreadCreationOutcome_UnknownOutcome() when unknownOutcome != null:
return unknownOutcome(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadCreationOutcome_Returned extends BridgeThreadCreationOutcome {
  const BridgeThreadCreationOutcome_Returned({required this.value}): super._();


 final  StartNewThreadResponse value;

/// Create a copy of BridgeThreadCreationOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadCreationOutcome_ReturnedCopyWith<BridgeThreadCreationOutcome_Returned> get copyWith => _$BridgeThreadCreationOutcome_ReturnedCopyWithImpl<BridgeThreadCreationOutcome_Returned>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadCreationOutcome_Returned&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeThreadCreationOutcome.returned(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadCreationOutcome_ReturnedCopyWith<$Res> implements $BridgeThreadCreationOutcomeCopyWith<$Res> {
  factory $BridgeThreadCreationOutcome_ReturnedCopyWith(BridgeThreadCreationOutcome_Returned value, $Res Function(BridgeThreadCreationOutcome_Returned) _then) = _$BridgeThreadCreationOutcome_ReturnedCopyWithImpl;
@useResult
$Res call({
 StartNewThreadResponse value
});




}
/// @nodoc
class _$BridgeThreadCreationOutcome_ReturnedCopyWithImpl<$Res>
    implements $BridgeThreadCreationOutcome_ReturnedCopyWith<$Res> {
  _$BridgeThreadCreationOutcome_ReturnedCopyWithImpl(this._self, this._then);

  final BridgeThreadCreationOutcome_Returned _self;
  final $Res Function(BridgeThreadCreationOutcome_Returned) _then;

/// Create a copy of BridgeThreadCreationOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeThreadCreationOutcome_Returned(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as StartNewThreadResponse,
  ));
}


}

/// @nodoc


class BridgeThreadCreationOutcome_Rejected extends BridgeThreadCreationOutcome {
  const BridgeThreadCreationOutcome_Rejected({required this.error}): super._();


 final  BridgeError error;

/// Create a copy of BridgeThreadCreationOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadCreationOutcome_RejectedCopyWith<BridgeThreadCreationOutcome_Rejected> get copyWith => _$BridgeThreadCreationOutcome_RejectedCopyWithImpl<BridgeThreadCreationOutcome_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadCreationOutcome_Rejected&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeThreadCreationOutcome.rejected(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadCreationOutcome_RejectedCopyWith<$Res> implements $BridgeThreadCreationOutcomeCopyWith<$Res> {
  factory $BridgeThreadCreationOutcome_RejectedCopyWith(BridgeThreadCreationOutcome_Rejected value, $Res Function(BridgeThreadCreationOutcome_Rejected) _then) = _$BridgeThreadCreationOutcome_RejectedCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeThreadCreationOutcome_RejectedCopyWithImpl<$Res>
    implements $BridgeThreadCreationOutcome_RejectedCopyWith<$Res> {
  _$BridgeThreadCreationOutcome_RejectedCopyWithImpl(this._self, this._then);

  final BridgeThreadCreationOutcome_Rejected _self;
  final $Res Function(BridgeThreadCreationOutcome_Rejected) _then;

/// Create a copy of BridgeThreadCreationOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeThreadCreationOutcome_Rejected(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeThreadCreationOutcome_UnknownOutcome extends BridgeThreadCreationOutcome {
  const BridgeThreadCreationOutcome_UnknownOutcome({required this.error}): super._();


 final  BridgeError error;

/// Create a copy of BridgeThreadCreationOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadCreationOutcome_UnknownOutcomeCopyWith<BridgeThreadCreationOutcome_UnknownOutcome> get copyWith => _$BridgeThreadCreationOutcome_UnknownOutcomeCopyWithImpl<BridgeThreadCreationOutcome_UnknownOutcome>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadCreationOutcome_UnknownOutcome&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeThreadCreationOutcome.unknownOutcome(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadCreationOutcome_UnknownOutcomeCopyWith<$Res> implements $BridgeThreadCreationOutcomeCopyWith<$Res> {
  factory $BridgeThreadCreationOutcome_UnknownOutcomeCopyWith(BridgeThreadCreationOutcome_UnknownOutcome value, $Res Function(BridgeThreadCreationOutcome_UnknownOutcome) _then) = _$BridgeThreadCreationOutcome_UnknownOutcomeCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeThreadCreationOutcome_UnknownOutcomeCopyWithImpl<$Res>
    implements $BridgeThreadCreationOutcome_UnknownOutcomeCopyWith<$Res> {
  _$BridgeThreadCreationOutcome_UnknownOutcomeCopyWithImpl(this._self, this._then);

  final BridgeThreadCreationOutcome_UnknownOutcome _self;
  final $Res Function(BridgeThreadCreationOutcome_UnknownOutcome) _then;

/// Create a copy of BridgeThreadCreationOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeThreadCreationOutcome_UnknownOutcome(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

// dart format on
