// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_directory.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAgentBinding {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentBinding);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAgentBinding()';
}


}

/// @nodoc
class $BridgeAgentBindingCopyWith<$Res>  {
$BridgeAgentBindingCopyWith(BridgeAgentBinding _, $Res Function(BridgeAgentBinding) __);
}


/// Adds pattern-matching-related methods to [BridgeAgentBinding].
extension BridgeAgentBindingPatterns on BridgeAgentBinding {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAgentBinding_Native value)?  native,TResult Function( BridgeAgentBinding_Acp value)?  acp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAgentBinding_Native() when native != null:
return native(_that);case BridgeAgentBinding_Acp() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAgentBinding_Native value)  native,required TResult Function( BridgeAgentBinding_Acp value)  acp,}){
final _that = this;
switch (_that) {
case BridgeAgentBinding_Native():
return native(_that);case BridgeAgentBinding_Acp():
return acp(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAgentBinding_Native value)?  native,TResult? Function( BridgeAgentBinding_Acp value)?  acp,}){
final _that = this;
switch (_that) {
case BridgeAgentBinding_Native() when native != null:
return native(_that);case BridgeAgentBinding_Acp() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeNewThreadModelRoute? route,  String? systemInstructions)?  native,TResult Function( String accountId,  BigInt connectionRevision)?  acp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAgentBinding_Native() when native != null:
return native(_that.route,_that.systemInstructions);case BridgeAgentBinding_Acp() when acp != null:
return acp(_that.accountId,_that.connectionRevision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeNewThreadModelRoute? route,  String? systemInstructions)  native,required TResult Function( String accountId,  BigInt connectionRevision)  acp,}) {final _that = this;
switch (_that) {
case BridgeAgentBinding_Native():
return native(_that.route,_that.systemInstructions);case BridgeAgentBinding_Acp():
return acp(_that.accountId,_that.connectionRevision);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeNewThreadModelRoute? route,  String? systemInstructions)?  native,TResult? Function( String accountId,  BigInt connectionRevision)?  acp,}) {final _that = this;
switch (_that) {
case BridgeAgentBinding_Native() when native != null:
return native(_that.route,_that.systemInstructions);case BridgeAgentBinding_Acp() when acp != null:
return acp(_that.accountId,_that.connectionRevision);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAgentBinding_Native extends BridgeAgentBinding {
  const BridgeAgentBinding_Native({this.route, this.systemInstructions}): super._();


 final  BridgeNewThreadModelRoute? route;
 final  String? systemInstructions;

/// Create a copy of BridgeAgentBinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentBinding_NativeCopyWith<BridgeAgentBinding_Native> get copyWith => _$BridgeAgentBinding_NativeCopyWithImpl<BridgeAgentBinding_Native>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentBinding_Native&&(identical(other.route, route) || other.route == route)&&(identical(other.systemInstructions, systemInstructions) || other.systemInstructions == systemInstructions));
}


@override
int get hashCode {
    return Object.hash(runtimeType,route,systemInstructions);
}

@override
String toString() {
    return 'BridgeAgentBinding.native(route: $route, systemInstructions: $systemInstructions)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentBinding_NativeCopyWith<$Res> implements $BridgeAgentBindingCopyWith<$Res> {
  factory $BridgeAgentBinding_NativeCopyWith(BridgeAgentBinding_Native value, $Res Function(BridgeAgentBinding_Native) _then) = _$BridgeAgentBinding_NativeCopyWithImpl;
@useResult
$Res call({
 BridgeNewThreadModelRoute? route, String? systemInstructions
});




}
/// @nodoc
class _$BridgeAgentBinding_NativeCopyWithImpl<$Res>
    implements $BridgeAgentBinding_NativeCopyWith<$Res> {
  _$BridgeAgentBinding_NativeCopyWithImpl(this._self, this._then);

  final BridgeAgentBinding_Native _self;
  final $Res Function(BridgeAgentBinding_Native) _then;

/// Create a copy of BridgeAgentBinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? route = freezed,Object? systemInstructions = freezed,}) {
  return _then(BridgeAgentBinding_Native(
route: freezed == route ? _self.route : route // ignore: cast_nullable_to_non_nullable
as BridgeNewThreadModelRoute?,systemInstructions: freezed == systemInstructions ? _self.systemInstructions : systemInstructions // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BridgeAgentBinding_Acp extends BridgeAgentBinding {
  const BridgeAgentBinding_Acp({required this.accountId, required this.connectionRevision}): super._();


 final  String accountId;
 final  BigInt connectionRevision;

/// Create a copy of BridgeAgentBinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentBinding_AcpCopyWith<BridgeAgentBinding_Acp> get copyWith => _$BridgeAgentBinding_AcpCopyWithImpl<BridgeAgentBinding_Acp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentBinding_Acp&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.connectionRevision, connectionRevision) || other.connectionRevision == connectionRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,connectionRevision);
}

@override
String toString() {
    return 'BridgeAgentBinding.acp(accountId: $accountId, connectionRevision: $connectionRevision)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentBinding_AcpCopyWith<$Res> implements $BridgeAgentBindingCopyWith<$Res> {
  factory $BridgeAgentBinding_AcpCopyWith(BridgeAgentBinding_Acp value, $Res Function(BridgeAgentBinding_Acp) _then) = _$BridgeAgentBinding_AcpCopyWithImpl;
@useResult
$Res call({
 String accountId, BigInt connectionRevision
});




}
/// @nodoc
class _$BridgeAgentBinding_AcpCopyWithImpl<$Res>
    implements $BridgeAgentBinding_AcpCopyWith<$Res> {
  _$BridgeAgentBinding_AcpCopyWithImpl(this._self, this._then);

  final BridgeAgentBinding_Acp _self;
  final $Res Function(BridgeAgentBinding_Acp) _then;

/// Create a copy of BridgeAgentBinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? connectionRevision = null,}) {
  return _then(BridgeAgentBinding_Acp(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,connectionRevision: null == connectionRevision ? _self.connectionRevision : connectionRevision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

// dart format on
