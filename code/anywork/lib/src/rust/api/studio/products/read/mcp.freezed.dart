// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mcp.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeMcpServerStateRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpServerStateRead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeMcpServerStateRead()';
}


}

/// @nodoc
class $BridgeMcpServerStateReadCopyWith<$Res>  {
$BridgeMcpServerStateReadCopyWith(BridgeMcpServerStateRead _, $Res Function(BridgeMcpServerStateRead) __);
}


/// Adds pattern-matching-related methods to [BridgeMcpServerStateRead].
extension BridgeMcpServerStateReadPatterns on BridgeMcpServerStateRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeMcpServerStateRead_Disabled value)?  disabled,TResult Function( BridgeMcpServerStateRead_MissingCredential value)?  missingCredential,TResult Function( BridgeMcpServerStateRead_Checking value)?  checking,TResult Function( BridgeMcpServerStateRead_Available value)?  available,TResult Function( BridgeMcpServerStateRead_Unavailable value)?  unavailable,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeMcpServerStateRead_Disabled() when disabled != null:
return disabled(_that);case BridgeMcpServerStateRead_MissingCredential() when missingCredential != null:
return missingCredential(_that);case BridgeMcpServerStateRead_Checking() when checking != null:
return checking(_that);case BridgeMcpServerStateRead_Available() when available != null:
return available(_that);case BridgeMcpServerStateRead_Unavailable() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeMcpServerStateRead_Disabled value)  disabled,required TResult Function( BridgeMcpServerStateRead_MissingCredential value)  missingCredential,required TResult Function( BridgeMcpServerStateRead_Checking value)  checking,required TResult Function( BridgeMcpServerStateRead_Available value)  available,required TResult Function( BridgeMcpServerStateRead_Unavailable value)  unavailable,}){
final _that = this;
switch (_that) {
case BridgeMcpServerStateRead_Disabled():
return disabled(_that);case BridgeMcpServerStateRead_MissingCredential():
return missingCredential(_that);case BridgeMcpServerStateRead_Checking():
return checking(_that);case BridgeMcpServerStateRead_Available():
return available(_that);case BridgeMcpServerStateRead_Unavailable():
return unavailable(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeMcpServerStateRead_Disabled value)?  disabled,TResult? Function( BridgeMcpServerStateRead_MissingCredential value)?  missingCredential,TResult? Function( BridgeMcpServerStateRead_Checking value)?  checking,TResult? Function( BridgeMcpServerStateRead_Available value)?  available,TResult? Function( BridgeMcpServerStateRead_Unavailable value)?  unavailable,}){
final _that = this;
switch (_that) {
case BridgeMcpServerStateRead_Disabled() when disabled != null:
return disabled(_that);case BridgeMcpServerStateRead_MissingCredential() when missingCredential != null:
return missingCredential(_that);case BridgeMcpServerStateRead_Checking() when checking != null:
return checking(_that);case BridgeMcpServerStateRead_Available() when available != null:
return available(_that);case BridgeMcpServerStateRead_Unavailable() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeReadText message)?  disabled,TResult Function( BridgeReadText message)?  missingCredential,TResult Function( BridgeReadText message)?  checking,TResult Function( PlatformInt64 checkedAt,  BigInt toolCount)?  available,TResult Function( PlatformInt64 checkedAt,  BridgeSourceStateErrorRead error)?  unavailable,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeMcpServerStateRead_Disabled() when disabled != null:
return disabled(_that.message);case BridgeMcpServerStateRead_MissingCredential() when missingCredential != null:
return missingCredential(_that.message);case BridgeMcpServerStateRead_Checking() when checking != null:
return checking(_that.message);case BridgeMcpServerStateRead_Available() when available != null:
return available(_that.checkedAt,_that.toolCount);case BridgeMcpServerStateRead_Unavailable() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeReadText message)  disabled,required TResult Function( BridgeReadText message)  missingCredential,required TResult Function( BridgeReadText message)  checking,required TResult Function( PlatformInt64 checkedAt,  BigInt toolCount)  available,required TResult Function( PlatformInt64 checkedAt,  BridgeSourceStateErrorRead error)  unavailable,}) {final _that = this;
switch (_that) {
case BridgeMcpServerStateRead_Disabled():
return disabled(_that.message);case BridgeMcpServerStateRead_MissingCredential():
return missingCredential(_that.message);case BridgeMcpServerStateRead_Checking():
return checking(_that.message);case BridgeMcpServerStateRead_Available():
return available(_that.checkedAt,_that.toolCount);case BridgeMcpServerStateRead_Unavailable():
return unavailable(_that.checkedAt,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeReadText message)?  disabled,TResult? Function( BridgeReadText message)?  missingCredential,TResult? Function( BridgeReadText message)?  checking,TResult? Function( PlatformInt64 checkedAt,  BigInt toolCount)?  available,TResult? Function( PlatformInt64 checkedAt,  BridgeSourceStateErrorRead error)?  unavailable,}) {final _that = this;
switch (_that) {
case BridgeMcpServerStateRead_Disabled() when disabled != null:
return disabled(_that.message);case BridgeMcpServerStateRead_MissingCredential() when missingCredential != null:
return missingCredential(_that.message);case BridgeMcpServerStateRead_Checking() when checking != null:
return checking(_that.message);case BridgeMcpServerStateRead_Available() when available != null:
return available(_that.checkedAt,_that.toolCount);case BridgeMcpServerStateRead_Unavailable() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeMcpServerStateRead_Disabled extends BridgeMcpServerStateRead {
  const BridgeMcpServerStateRead_Disabled({required this.message}): super._();


 final  BridgeReadText message;

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpServerStateRead_DisabledCopyWith<BridgeMcpServerStateRead_Disabled> get copyWith => _$BridgeMcpServerStateRead_DisabledCopyWithImpl<BridgeMcpServerStateRead_Disabled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpServerStateRead_Disabled&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'BridgeMcpServerStateRead.disabled(message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpServerStateRead_DisabledCopyWith<$Res> implements $BridgeMcpServerStateReadCopyWith<$Res> {
  factory $BridgeMcpServerStateRead_DisabledCopyWith(BridgeMcpServerStateRead_Disabled value, $Res Function(BridgeMcpServerStateRead_Disabled) _then) = _$BridgeMcpServerStateRead_DisabledCopyWithImpl;
@useResult
$Res call({
 BridgeReadText message
});


$BridgeReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$BridgeMcpServerStateRead_DisabledCopyWithImpl<$Res>
    implements $BridgeMcpServerStateRead_DisabledCopyWith<$Res> {
  _$BridgeMcpServerStateRead_DisabledCopyWithImpl(this._self, this._then);

  final BridgeMcpServerStateRead_Disabled _self;
  final $Res Function(BridgeMcpServerStateRead_Disabled) _then;

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(BridgeMcpServerStateRead_Disabled(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get message {

  return $BridgeReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc


class BridgeMcpServerStateRead_MissingCredential extends BridgeMcpServerStateRead {
  const BridgeMcpServerStateRead_MissingCredential({required this.message}): super._();


 final  BridgeReadText message;

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpServerStateRead_MissingCredentialCopyWith<BridgeMcpServerStateRead_MissingCredential> get copyWith => _$BridgeMcpServerStateRead_MissingCredentialCopyWithImpl<BridgeMcpServerStateRead_MissingCredential>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpServerStateRead_MissingCredential&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'BridgeMcpServerStateRead.missingCredential(message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpServerStateRead_MissingCredentialCopyWith<$Res> implements $BridgeMcpServerStateReadCopyWith<$Res> {
  factory $BridgeMcpServerStateRead_MissingCredentialCopyWith(BridgeMcpServerStateRead_MissingCredential value, $Res Function(BridgeMcpServerStateRead_MissingCredential) _then) = _$BridgeMcpServerStateRead_MissingCredentialCopyWithImpl;
@useResult
$Res call({
 BridgeReadText message
});


$BridgeReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$BridgeMcpServerStateRead_MissingCredentialCopyWithImpl<$Res>
    implements $BridgeMcpServerStateRead_MissingCredentialCopyWith<$Res> {
  _$BridgeMcpServerStateRead_MissingCredentialCopyWithImpl(this._self, this._then);

  final BridgeMcpServerStateRead_MissingCredential _self;
  final $Res Function(BridgeMcpServerStateRead_MissingCredential) _then;

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(BridgeMcpServerStateRead_MissingCredential(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get message {

  return $BridgeReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc


class BridgeMcpServerStateRead_Checking extends BridgeMcpServerStateRead {
  const BridgeMcpServerStateRead_Checking({required this.message}): super._();


 final  BridgeReadText message;

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpServerStateRead_CheckingCopyWith<BridgeMcpServerStateRead_Checking> get copyWith => _$BridgeMcpServerStateRead_CheckingCopyWithImpl<BridgeMcpServerStateRead_Checking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpServerStateRead_Checking&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'BridgeMcpServerStateRead.checking(message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpServerStateRead_CheckingCopyWith<$Res> implements $BridgeMcpServerStateReadCopyWith<$Res> {
  factory $BridgeMcpServerStateRead_CheckingCopyWith(BridgeMcpServerStateRead_Checking value, $Res Function(BridgeMcpServerStateRead_Checking) _then) = _$BridgeMcpServerStateRead_CheckingCopyWithImpl;
@useResult
$Res call({
 BridgeReadText message
});


$BridgeReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$BridgeMcpServerStateRead_CheckingCopyWithImpl<$Res>
    implements $BridgeMcpServerStateRead_CheckingCopyWith<$Res> {
  _$BridgeMcpServerStateRead_CheckingCopyWithImpl(this._self, this._then);

  final BridgeMcpServerStateRead_Checking _self;
  final $Res Function(BridgeMcpServerStateRead_Checking) _then;

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(BridgeMcpServerStateRead_Checking(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get message {

  return $BridgeReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc


class BridgeMcpServerStateRead_Available extends BridgeMcpServerStateRead {
  const BridgeMcpServerStateRead_Available({required this.checkedAt, required this.toolCount}): super._();


 final  PlatformInt64 checkedAt;
 final  BigInt toolCount;

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpServerStateRead_AvailableCopyWith<BridgeMcpServerStateRead_Available> get copyWith => _$BridgeMcpServerStateRead_AvailableCopyWithImpl<BridgeMcpServerStateRead_Available>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpServerStateRead_Available&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.toolCount, toolCount) || other.toolCount == toolCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,toolCount);
}

@override
String toString() {
    return 'BridgeMcpServerStateRead.available(checkedAt: $checkedAt, toolCount: $toolCount)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpServerStateRead_AvailableCopyWith<$Res> implements $BridgeMcpServerStateReadCopyWith<$Res> {
  factory $BridgeMcpServerStateRead_AvailableCopyWith(BridgeMcpServerStateRead_Available value, $Res Function(BridgeMcpServerStateRead_Available) _then) = _$BridgeMcpServerStateRead_AvailableCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 checkedAt, BigInt toolCount
});




}
/// @nodoc
class _$BridgeMcpServerStateRead_AvailableCopyWithImpl<$Res>
    implements $BridgeMcpServerStateRead_AvailableCopyWith<$Res> {
  _$BridgeMcpServerStateRead_AvailableCopyWithImpl(this._self, this._then);

  final BridgeMcpServerStateRead_Available _self;
  final $Res Function(BridgeMcpServerStateRead_Available) _then;

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? toolCount = null,}) {
  return _then(BridgeMcpServerStateRead_Available(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,toolCount: null == toolCount ? _self.toolCount : toolCount // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeMcpServerStateRead_Unavailable extends BridgeMcpServerStateRead {
  const BridgeMcpServerStateRead_Unavailable({required this.checkedAt, required this.error}): super._();


 final  PlatformInt64 checkedAt;
 final  BridgeSourceStateErrorRead error;

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeMcpServerStateRead_UnavailableCopyWith<BridgeMcpServerStateRead_Unavailable> get copyWith => _$BridgeMcpServerStateRead_UnavailableCopyWithImpl<BridgeMcpServerStateRead_Unavailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeMcpServerStateRead_Unavailable&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,error);
}

@override
String toString() {
    return 'BridgeMcpServerStateRead.unavailable(checkedAt: $checkedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeMcpServerStateRead_UnavailableCopyWith<$Res> implements $BridgeMcpServerStateReadCopyWith<$Res> {
  factory $BridgeMcpServerStateRead_UnavailableCopyWith(BridgeMcpServerStateRead_Unavailable value, $Res Function(BridgeMcpServerStateRead_Unavailable) _then) = _$BridgeMcpServerStateRead_UnavailableCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 checkedAt, BridgeSourceStateErrorRead error
});




}
/// @nodoc
class _$BridgeMcpServerStateRead_UnavailableCopyWithImpl<$Res>
    implements $BridgeMcpServerStateRead_UnavailableCopyWith<$Res> {
  _$BridgeMcpServerStateRead_UnavailableCopyWithImpl(this._self, this._then);

  final BridgeMcpServerStateRead_Unavailable _self;
  final $Res Function(BridgeMcpServerStateRead_Unavailable) _then;

/// Create a copy of BridgeMcpServerStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? error = null,}) {
  return _then(BridgeMcpServerStateRead_Unavailable(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeSourceStateErrorRead,
  ));
}


}

// dart format on
