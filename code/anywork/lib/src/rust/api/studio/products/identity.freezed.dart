// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'identity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeProductReadVersion {

 BigInt get entry; BigInt get revision;
/// Create a copy of BridgeProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductReadVersionCopyWith<BridgeProductReadVersion> get copyWith => _$BridgeProductReadVersionCopyWithImpl<BridgeProductReadVersion>(this as BridgeProductReadVersion, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeProductReadVersion;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductReadVersion&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as BridgeProductReadVersion;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as BridgeProductReadVersion;
  return 'BridgeProductReadVersion(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $BridgeProductReadVersionCopyWith<$Res>  {
  factory $BridgeProductReadVersionCopyWith(BridgeProductReadVersion value, $Res Function(BridgeProductReadVersion) _then) = _$BridgeProductReadVersionCopyWithImpl;
@useResult
$Res call({
 BigInt entry, BigInt revision
});




}
/// @nodoc
class _$BridgeProductReadVersionCopyWithImpl<$Res>
    implements $BridgeProductReadVersionCopyWith<$Res> {
  _$BridgeProductReadVersionCopyWithImpl(this._self, this._then);

  final BridgeProductReadVersion _self;
  final $Res Function(BridgeProductReadVersion) _then;

/// Create a copy of BridgeProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_self.copyWith(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as BigInt,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeProductReadVersion].
extension BridgeProductReadVersionPatterns on BridgeProductReadVersion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeProductReadVersion_Value value)?  value,TResult Function( BridgeProductReadVersion_SourceStatus value)?  sourceStatus,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeProductReadVersion_Value() when value != null:
return value(_that);case BridgeProductReadVersion_SourceStatus() when sourceStatus != null:
return sourceStatus(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeProductReadVersion_Value value)  value,required TResult Function( BridgeProductReadVersion_SourceStatus value)  sourceStatus,}){
final _that = this;
switch (_that) {
case BridgeProductReadVersion_Value():
return value(_that);case BridgeProductReadVersion_SourceStatus():
return sourceStatus(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeProductReadVersion_Value value)?  value,TResult? Function( BridgeProductReadVersion_SourceStatus value)?  sourceStatus,}){
final _that = this;
switch (_that) {
case BridgeProductReadVersion_Value() when value != null:
return value(_that);case BridgeProductReadVersion_SourceStatus() when sourceStatus != null:
return sourceStatus(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt entry,  BigInt revision)?  value,TResult Function( BigInt entry,  BigInt revision)?  sourceStatus,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeProductReadVersion_Value() when value != null:
return value(_that.entry,_that.revision);case BridgeProductReadVersion_SourceStatus() when sourceStatus != null:
return sourceStatus(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt entry,  BigInt revision)  value,required TResult Function( BigInt entry,  BigInt revision)  sourceStatus,}) {final _that = this;
switch (_that) {
case BridgeProductReadVersion_Value():
return value(_that.entry,_that.revision);case BridgeProductReadVersion_SourceStatus():
return sourceStatus(_that.entry,_that.revision);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt entry,  BigInt revision)?  value,TResult? Function( BigInt entry,  BigInt revision)?  sourceStatus,}) {final _that = this;
switch (_that) {
case BridgeProductReadVersion_Value() when value != null:
return value(_that.entry,_that.revision);case BridgeProductReadVersion_SourceStatus() when sourceStatus != null:
return sourceStatus(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class BridgeProductReadVersion_Value extends BridgeProductReadVersion {
  const BridgeProductReadVersion_Value({required this.entry, required this.revision}): super._();


@override final  BigInt entry;
@override final  BigInt revision;

/// Create a copy of BridgeProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductReadVersion_ValueCopyWith<BridgeProductReadVersion_Value> get copyWith => _$BridgeProductReadVersion_ValueCopyWithImpl<BridgeProductReadVersion_Value>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductReadVersion_Value&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'BridgeProductReadVersion.value(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $BridgeProductReadVersion_ValueCopyWith<$Res> implements $BridgeProductReadVersionCopyWith<$Res> {
  factory $BridgeProductReadVersion_ValueCopyWith(BridgeProductReadVersion_Value value, $Res Function(BridgeProductReadVersion_Value) _then) = _$BridgeProductReadVersion_ValueCopyWithImpl;
@override @useResult
$Res call({
 BigInt entry, BigInt revision
});




}
/// @nodoc
class _$BridgeProductReadVersion_ValueCopyWithImpl<$Res>
    implements $BridgeProductReadVersion_ValueCopyWith<$Res> {
  _$BridgeProductReadVersion_ValueCopyWithImpl(this._self, this._then);

  final BridgeProductReadVersion_Value _self;
  final $Res Function(BridgeProductReadVersion_Value) _then;

/// Create a copy of BridgeProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(BridgeProductReadVersion_Value(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as BigInt,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeProductReadVersion_SourceStatus extends BridgeProductReadVersion {
  const BridgeProductReadVersion_SourceStatus({required this.entry, required this.revision}): super._();


@override final  BigInt entry;
@override final  BigInt revision;

/// Create a copy of BridgeProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductReadVersion_SourceStatusCopyWith<BridgeProductReadVersion_SourceStatus> get copyWith => _$BridgeProductReadVersion_SourceStatusCopyWithImpl<BridgeProductReadVersion_SourceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductReadVersion_SourceStatus&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'BridgeProductReadVersion.sourceStatus(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $BridgeProductReadVersion_SourceStatusCopyWith<$Res> implements $BridgeProductReadVersionCopyWith<$Res> {
  factory $BridgeProductReadVersion_SourceStatusCopyWith(BridgeProductReadVersion_SourceStatus value, $Res Function(BridgeProductReadVersion_SourceStatus) _then) = _$BridgeProductReadVersion_SourceStatusCopyWithImpl;
@override @useResult
$Res call({
 BigInt entry, BigInt revision
});




}
/// @nodoc
class _$BridgeProductReadVersion_SourceStatusCopyWithImpl<$Res>
    implements $BridgeProductReadVersion_SourceStatusCopyWith<$Res> {
  _$BridgeProductReadVersion_SourceStatusCopyWithImpl(this._self, this._then);

  final BridgeProductReadVersion_SourceStatus _self;
  final $Res Function(BridgeProductReadVersion_SourceStatus) _then;

/// Create a copy of BridgeProductReadVersion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(BridgeProductReadVersion_SourceStatus(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as BigInt,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

// dart format on
