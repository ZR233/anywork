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
mixin _$BridgeAgentBackend {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentBackend);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAgentBackend()';
}


}

/// @nodoc
class $BridgeAgentBackendCopyWith<$Res>  {
$BridgeAgentBackendCopyWith(BridgeAgentBackend _, $Res Function(BridgeAgentBackend) __);
}


/// Adds pattern-matching-related methods to [BridgeAgentBackend].
extension BridgeAgentBackendPatterns on BridgeAgentBackend {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAgentBackend_Native value)?  native,TResult Function( BridgeAgentBackend_Acp value)?  acp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAgentBackend_Native() when native != null:
return native(_that);case BridgeAgentBackend_Acp() when acp != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAgentBackend_Native value)  native,required TResult Function( BridgeAgentBackend_Acp value)  acp,}){
final _that = this;
switch (_that) {
case BridgeAgentBackend_Native():
return native(_that);case BridgeAgentBackend_Acp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAgentBackend_Native value)?  native,TResult? Function( BridgeAgentBackend_Acp value)?  acp,}){
final _that = this;
switch (_that) {
case BridgeAgentBackend_Native() when native != null:
return native(_that);case BridgeAgentBackend_Acp() when acp != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeNativeAgentConfig config,  BridgeThreadStatus status)?  native,TResult Function( BridgeAcpSessionReference reference)?  acp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAgentBackend_Native() when native != null:
return native(_that.config,_that.status);case BridgeAgentBackend_Acp() when acp != null:
return acp(_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeNativeAgentConfig config,  BridgeThreadStatus status)  native,required TResult Function( BridgeAcpSessionReference reference)  acp,}) {final _that = this;
switch (_that) {
case BridgeAgentBackend_Native():
return native(_that.config,_that.status);case BridgeAgentBackend_Acp():
return acp(_that.reference);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeNativeAgentConfig config,  BridgeThreadStatus status)?  native,TResult? Function( BridgeAcpSessionReference reference)?  acp,}) {final _that = this;
switch (_that) {
case BridgeAgentBackend_Native() when native != null:
return native(_that.config,_that.status);case BridgeAgentBackend_Acp() when acp != null:
return acp(_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAgentBackend_Native extends BridgeAgentBackend {
  const BridgeAgentBackend_Native({required this.config, required this.status}): super._();


 final  BridgeNativeAgentConfig config;
 final  BridgeThreadStatus status;

/// Create a copy of BridgeAgentBackend
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentBackend_NativeCopyWith<BridgeAgentBackend_Native> get copyWith => _$BridgeAgentBackend_NativeCopyWithImpl<BridgeAgentBackend_Native>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentBackend_Native&&(identical(other.config, config) || other.config == config)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,config,status);
}

@override
String toString() {
    return 'BridgeAgentBackend.native(config: $config, status: $status)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentBackend_NativeCopyWith<$Res> implements $BridgeAgentBackendCopyWith<$Res> {
  factory $BridgeAgentBackend_NativeCopyWith(BridgeAgentBackend_Native value, $Res Function(BridgeAgentBackend_Native) _then) = _$BridgeAgentBackend_NativeCopyWithImpl;
@useResult
$Res call({
 BridgeNativeAgentConfig config, BridgeThreadStatus status
});




}
/// @nodoc
class _$BridgeAgentBackend_NativeCopyWithImpl<$Res>
    implements $BridgeAgentBackend_NativeCopyWith<$Res> {
  _$BridgeAgentBackend_NativeCopyWithImpl(this._self, this._then);

  final BridgeAgentBackend_Native _self;
  final $Res Function(BridgeAgentBackend_Native) _then;

/// Create a copy of BridgeAgentBackend
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? config = null,Object? status = null,}) {
  return _then(BridgeAgentBackend_Native(
config: null == config ? _self.config : config // ignore: cast_nullable_to_non_nullable
as BridgeNativeAgentConfig,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BridgeThreadStatus,
  ));
}


}

/// @nodoc


class BridgeAgentBackend_Acp extends BridgeAgentBackend {
  const BridgeAgentBackend_Acp({required this.reference}): super._();


 final  BridgeAcpSessionReference reference;

/// Create a copy of BridgeAgentBackend
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentBackend_AcpCopyWith<BridgeAgentBackend_Acp> get copyWith => _$BridgeAgentBackend_AcpCopyWithImpl<BridgeAgentBackend_Acp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentBackend_Acp&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference);
}

@override
String toString() {
    return 'BridgeAgentBackend.acp(reference: $reference)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentBackend_AcpCopyWith<$Res> implements $BridgeAgentBackendCopyWith<$Res> {
  factory $BridgeAgentBackend_AcpCopyWith(BridgeAgentBackend_Acp value, $Res Function(BridgeAgentBackend_Acp) _then) = _$BridgeAgentBackend_AcpCopyWithImpl;
@useResult
$Res call({
 BridgeAcpSessionReference reference
});




}
/// @nodoc
class _$BridgeAgentBackend_AcpCopyWithImpl<$Res>
    implements $BridgeAgentBackend_AcpCopyWith<$Res> {
  _$BridgeAgentBackend_AcpCopyWithImpl(this._self, this._then);

  final BridgeAgentBackend_Acp _self;
  final $Res Function(BridgeAgentBackend_Acp) _then;

/// Create a copy of BridgeAgentBackend
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reference = null,}) {
  return _then(BridgeAgentBackend_Acp(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as BridgeAcpSessionReference,
  ));
}


}

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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeNewThreadModelRoute? route,  String? systemInstructions)?  native,TResult Function( String accountId)?  acp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAgentBinding_Native() when native != null:
return native(_that.route,_that.systemInstructions);case BridgeAgentBinding_Acp() when acp != null:
return acp(_that.accountId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeNewThreadModelRoute? route,  String? systemInstructions)  native,required TResult Function( String accountId)  acp,}) {final _that = this;
switch (_that) {
case BridgeAgentBinding_Native():
return native(_that.route,_that.systemInstructions);case BridgeAgentBinding_Acp():
return acp(_that.accountId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeNewThreadModelRoute? route,  String? systemInstructions)?  native,TResult? Function( String accountId)?  acp,}) {final _that = this;
switch (_that) {
case BridgeAgentBinding_Native() when native != null:
return native(_that.route,_that.systemInstructions);case BridgeAgentBinding_Acp() when acp != null:
return acp(_that.accountId);case _:
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
  const BridgeAgentBinding_Acp({required this.accountId}): super._();


 final  String accountId;

/// Create a copy of BridgeAgentBinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentBinding_AcpCopyWith<BridgeAgentBinding_Acp> get copyWith => _$BridgeAgentBinding_AcpCopyWithImpl<BridgeAgentBinding_Acp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentBinding_Acp&&(identical(other.accountId, accountId) || other.accountId == accountId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId);
}

@override
String toString() {
    return 'BridgeAgentBinding.acp(accountId: $accountId)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentBinding_AcpCopyWith<$Res> implements $BridgeAgentBindingCopyWith<$Res> {
  factory $BridgeAgentBinding_AcpCopyWith(BridgeAgentBinding_Acp value, $Res Function(BridgeAgentBinding_Acp) _then) = _$BridgeAgentBinding_AcpCopyWithImpl;
@useResult
$Res call({
 String accountId
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
@pragma('vm:prefer-inline') $Res call({Object? accountId = null,}) {
  return _then(BridgeAgentBinding_Acp(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
