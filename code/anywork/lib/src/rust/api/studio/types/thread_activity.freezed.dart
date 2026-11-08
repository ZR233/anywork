// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_activity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeActivityIdentity {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityIdentity);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeActivityIdentity()';
}


}

/// @nodoc
class $BridgeActivityIdentityCopyWith<$Res>  {
$BridgeActivityIdentityCopyWith(BridgeActivityIdentity _, $Res Function(BridgeActivityIdentity) __);
}


/// Adds pattern-matching-related methods to [BridgeActivityIdentity].
extension BridgeActivityIdentityPatterns on BridgeActivityIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeActivityIdentity_ModelPart value)?  modelPart,TResult Function( BridgeActivityIdentity_ForegroundTool value)?  foregroundTool,TResult Function( BridgeActivityIdentity_BackgroundTool value)?  backgroundTool,TResult Function( BridgeActivityIdentity_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeActivityIdentity_ModelPart() when modelPart != null:
return modelPart(_that);case BridgeActivityIdentity_ForegroundTool() when foregroundTool != null:
return foregroundTool(_that);case BridgeActivityIdentity_BackgroundTool() when backgroundTool != null:
return backgroundTool(_that);case BridgeActivityIdentity_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeActivityIdentity_ModelPart value)  modelPart,required TResult Function( BridgeActivityIdentity_ForegroundTool value)  foregroundTool,required TResult Function( BridgeActivityIdentity_BackgroundTool value)  backgroundTool,required TResult Function( BridgeActivityIdentity_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeActivityIdentity_ModelPart():
return modelPart(_that);case BridgeActivityIdentity_ForegroundTool():
return foregroundTool(_that);case BridgeActivityIdentity_BackgroundTool():
return backgroundTool(_that);case BridgeActivityIdentity_Other():
return other(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeActivityIdentity_ModelPart value)?  modelPart,TResult? Function( BridgeActivityIdentity_ForegroundTool value)?  foregroundTool,TResult? Function( BridgeActivityIdentity_BackgroundTool value)?  backgroundTool,TResult? Function( BridgeActivityIdentity_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeActivityIdentity_ModelPart() when modelPart != null:
return modelPart(_that);case BridgeActivityIdentity_ForegroundTool() when foregroundTool != null:
return foregroundTool(_that);case BridgeActivityIdentity_BackgroundTool() when backgroundTool != null:
return backgroundTool(_that);case BridgeActivityIdentity_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String atomId)?  modelPart,TResult Function( String callId)?  foregroundTool,TResult Function( String callId)?  backgroundTool,TResult Function( String domain,  String id)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeActivityIdentity_ModelPart() when modelPart != null:
return modelPart(_that.atomId);case BridgeActivityIdentity_ForegroundTool() when foregroundTool != null:
return foregroundTool(_that.callId);case BridgeActivityIdentity_BackgroundTool() when backgroundTool != null:
return backgroundTool(_that.callId);case BridgeActivityIdentity_Other() when other != null:
return other(_that.domain,_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String atomId)  modelPart,required TResult Function( String callId)  foregroundTool,required TResult Function( String callId)  backgroundTool,required TResult Function( String domain,  String id)  other,}) {final _that = this;
switch (_that) {
case BridgeActivityIdentity_ModelPart():
return modelPart(_that.atomId);case BridgeActivityIdentity_ForegroundTool():
return foregroundTool(_that.callId);case BridgeActivityIdentity_BackgroundTool():
return backgroundTool(_that.callId);case BridgeActivityIdentity_Other():
return other(_that.domain,_that.id);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String atomId)?  modelPart,TResult? Function( String callId)?  foregroundTool,TResult? Function( String callId)?  backgroundTool,TResult? Function( String domain,  String id)?  other,}) {final _that = this;
switch (_that) {
case BridgeActivityIdentity_ModelPart() when modelPart != null:
return modelPart(_that.atomId);case BridgeActivityIdentity_ForegroundTool() when foregroundTool != null:
return foregroundTool(_that.callId);case BridgeActivityIdentity_BackgroundTool() when backgroundTool != null:
return backgroundTool(_that.callId);case BridgeActivityIdentity_Other() when other != null:
return other(_that.domain,_that.id);case _:
  return null;

}
}

}

/// @nodoc


class BridgeActivityIdentity_ModelPart extends BridgeActivityIdentity {
  const BridgeActivityIdentity_ModelPart({required this.atomId}): super._();


 final  String atomId;

/// Create a copy of BridgeActivityIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityIdentity_ModelPartCopyWith<BridgeActivityIdentity_ModelPart> get copyWith => _$BridgeActivityIdentity_ModelPartCopyWithImpl<BridgeActivityIdentity_ModelPart>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityIdentity_ModelPart&&(identical(other.atomId, atomId) || other.atomId == atomId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,atomId);
}

@override
String toString() {
    return 'BridgeActivityIdentity.modelPart(atomId: $atomId)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityIdentity_ModelPartCopyWith<$Res> implements $BridgeActivityIdentityCopyWith<$Res> {
  factory $BridgeActivityIdentity_ModelPartCopyWith(BridgeActivityIdentity_ModelPart value, $Res Function(BridgeActivityIdentity_ModelPart) _then) = _$BridgeActivityIdentity_ModelPartCopyWithImpl;
@useResult
$Res call({
 String atomId
});




}
/// @nodoc
class _$BridgeActivityIdentity_ModelPartCopyWithImpl<$Res>
    implements $BridgeActivityIdentity_ModelPartCopyWith<$Res> {
  _$BridgeActivityIdentity_ModelPartCopyWithImpl(this._self, this._then);

  final BridgeActivityIdentity_ModelPart _self;
  final $Res Function(BridgeActivityIdentity_ModelPart) _then;

/// Create a copy of BridgeActivityIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? atomId = null,}) {
  return _then(BridgeActivityIdentity_ModelPart(
atomId: null == atomId ? _self.atomId : atomId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeActivityIdentity_ForegroundTool extends BridgeActivityIdentity {
  const BridgeActivityIdentity_ForegroundTool({required this.callId}): super._();


 final  String callId;

/// Create a copy of BridgeActivityIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityIdentity_ForegroundToolCopyWith<BridgeActivityIdentity_ForegroundTool> get copyWith => _$BridgeActivityIdentity_ForegroundToolCopyWithImpl<BridgeActivityIdentity_ForegroundTool>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityIdentity_ForegroundTool&&(identical(other.callId, callId) || other.callId == callId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,callId);
}

@override
String toString() {
    return 'BridgeActivityIdentity.foregroundTool(callId: $callId)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityIdentity_ForegroundToolCopyWith<$Res> implements $BridgeActivityIdentityCopyWith<$Res> {
  factory $BridgeActivityIdentity_ForegroundToolCopyWith(BridgeActivityIdentity_ForegroundTool value, $Res Function(BridgeActivityIdentity_ForegroundTool) _then) = _$BridgeActivityIdentity_ForegroundToolCopyWithImpl;
@useResult
$Res call({
 String callId
});




}
/// @nodoc
class _$BridgeActivityIdentity_ForegroundToolCopyWithImpl<$Res>
    implements $BridgeActivityIdentity_ForegroundToolCopyWith<$Res> {
  _$BridgeActivityIdentity_ForegroundToolCopyWithImpl(this._self, this._then);

  final BridgeActivityIdentity_ForegroundTool _self;
  final $Res Function(BridgeActivityIdentity_ForegroundTool) _then;

/// Create a copy of BridgeActivityIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? callId = null,}) {
  return _then(BridgeActivityIdentity_ForegroundTool(
callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeActivityIdentity_BackgroundTool extends BridgeActivityIdentity {
  const BridgeActivityIdentity_BackgroundTool({required this.callId}): super._();


 final  String callId;

/// Create a copy of BridgeActivityIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityIdentity_BackgroundToolCopyWith<BridgeActivityIdentity_BackgroundTool> get copyWith => _$BridgeActivityIdentity_BackgroundToolCopyWithImpl<BridgeActivityIdentity_BackgroundTool>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityIdentity_BackgroundTool&&(identical(other.callId, callId) || other.callId == callId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,callId);
}

@override
String toString() {
    return 'BridgeActivityIdentity.backgroundTool(callId: $callId)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityIdentity_BackgroundToolCopyWith<$Res> implements $BridgeActivityIdentityCopyWith<$Res> {
  factory $BridgeActivityIdentity_BackgroundToolCopyWith(BridgeActivityIdentity_BackgroundTool value, $Res Function(BridgeActivityIdentity_BackgroundTool) _then) = _$BridgeActivityIdentity_BackgroundToolCopyWithImpl;
@useResult
$Res call({
 String callId
});




}
/// @nodoc
class _$BridgeActivityIdentity_BackgroundToolCopyWithImpl<$Res>
    implements $BridgeActivityIdentity_BackgroundToolCopyWith<$Res> {
  _$BridgeActivityIdentity_BackgroundToolCopyWithImpl(this._self, this._then);

  final BridgeActivityIdentity_BackgroundTool _self;
  final $Res Function(BridgeActivityIdentity_BackgroundTool) _then;

/// Create a copy of BridgeActivityIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? callId = null,}) {
  return _then(BridgeActivityIdentity_BackgroundTool(
callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeActivityIdentity_Other extends BridgeActivityIdentity {
  const BridgeActivityIdentity_Other({required this.domain, required this.id}): super._();


 final  String domain;
 final  String id;

/// Create a copy of BridgeActivityIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeActivityIdentity_OtherCopyWith<BridgeActivityIdentity_Other> get copyWith => _$BridgeActivityIdentity_OtherCopyWithImpl<BridgeActivityIdentity_Other>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeActivityIdentity_Other&&(identical(other.domain, domain) || other.domain == domain)&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,domain,id);
}

@override
String toString() {
    return 'BridgeActivityIdentity.other(domain: $domain, id: $id)';
}


}

/// @nodoc
abstract mixin class $BridgeActivityIdentity_OtherCopyWith<$Res> implements $BridgeActivityIdentityCopyWith<$Res> {
  factory $BridgeActivityIdentity_OtherCopyWith(BridgeActivityIdentity_Other value, $Res Function(BridgeActivityIdentity_Other) _then) = _$BridgeActivityIdentity_OtherCopyWithImpl;
@useResult
$Res call({
 String domain, String id
});




}
/// @nodoc
class _$BridgeActivityIdentity_OtherCopyWithImpl<$Res>
    implements $BridgeActivityIdentity_OtherCopyWith<$Res> {
  _$BridgeActivityIdentity_OtherCopyWithImpl(this._self, this._then);

  final BridgeActivityIdentity_Other _self;
  final $Res Function(BridgeActivityIdentity_Other) _then;

/// Create a copy of BridgeActivityIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? domain = null,Object? id = null,}) {
  return _then(BridgeActivityIdentity_Other(
domain: null == domain ? _self.domain : domain // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
