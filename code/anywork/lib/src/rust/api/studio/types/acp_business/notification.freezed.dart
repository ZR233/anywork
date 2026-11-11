// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'notification.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAcpCompactionStatus {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpCompactionStatus);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpCompactionStatus()';
}


}

/// @nodoc
class $BridgeAcpCompactionStatusCopyWith<$Res>  {
$BridgeAcpCompactionStatusCopyWith(BridgeAcpCompactionStatus _, $Res Function(BridgeAcpCompactionStatus) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpCompactionStatus].
extension BridgeAcpCompactionStatusPatterns on BridgeAcpCompactionStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpCompactionStatus_InProgress value)?  inProgress,TResult Function( BridgeAcpCompactionStatus_Completed value)?  completed,TResult Function( BridgeAcpCompactionStatus_Failed value)?  failed,TResult Function( BridgeAcpCompactionStatus_Cancelled value)?  cancelled,TResult Function( BridgeAcpCompactionStatus_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpCompactionStatus_InProgress() when inProgress != null:
return inProgress(_that);case BridgeAcpCompactionStatus_Completed() when completed != null:
return completed(_that);case BridgeAcpCompactionStatus_Failed() when failed != null:
return failed(_that);case BridgeAcpCompactionStatus_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeAcpCompactionStatus_Other() when other != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpCompactionStatus_InProgress value)  inProgress,required TResult Function( BridgeAcpCompactionStatus_Completed value)  completed,required TResult Function( BridgeAcpCompactionStatus_Failed value)  failed,required TResult Function( BridgeAcpCompactionStatus_Cancelled value)  cancelled,required TResult Function( BridgeAcpCompactionStatus_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeAcpCompactionStatus_InProgress():
return inProgress(_that);case BridgeAcpCompactionStatus_Completed():
return completed(_that);case BridgeAcpCompactionStatus_Failed():
return failed(_that);case BridgeAcpCompactionStatus_Cancelled():
return cancelled(_that);case BridgeAcpCompactionStatus_Other():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpCompactionStatus_InProgress value)?  inProgress,TResult? Function( BridgeAcpCompactionStatus_Completed value)?  completed,TResult? Function( BridgeAcpCompactionStatus_Failed value)?  failed,TResult? Function( BridgeAcpCompactionStatus_Cancelled value)?  cancelled,TResult? Function( BridgeAcpCompactionStatus_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeAcpCompactionStatus_InProgress() when inProgress != null:
return inProgress(_that);case BridgeAcpCompactionStatus_Completed() when completed != null:
return completed(_that);case BridgeAcpCompactionStatus_Failed() when failed != null:
return failed(_that);case BridgeAcpCompactionStatus_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeAcpCompactionStatus_Other() when other != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  inProgress,TResult Function()?  completed,TResult Function()?  failed,TResult Function()?  cancelled,TResult Function( String value)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpCompactionStatus_InProgress() when inProgress != null:
return inProgress();case BridgeAcpCompactionStatus_Completed() when completed != null:
return completed();case BridgeAcpCompactionStatus_Failed() when failed != null:
return failed();case BridgeAcpCompactionStatus_Cancelled() when cancelled != null:
return cancelled();case BridgeAcpCompactionStatus_Other() when other != null:
return other(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  inProgress,required TResult Function()  completed,required TResult Function()  failed,required TResult Function()  cancelled,required TResult Function( String value)  other,}) {final _that = this;
switch (_that) {
case BridgeAcpCompactionStatus_InProgress():
return inProgress();case BridgeAcpCompactionStatus_Completed():
return completed();case BridgeAcpCompactionStatus_Failed():
return failed();case BridgeAcpCompactionStatus_Cancelled():
return cancelled();case BridgeAcpCompactionStatus_Other():
return other(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  inProgress,TResult? Function()?  completed,TResult? Function()?  failed,TResult? Function()?  cancelled,TResult? Function( String value)?  other,}) {final _that = this;
switch (_that) {
case BridgeAcpCompactionStatus_InProgress() when inProgress != null:
return inProgress();case BridgeAcpCompactionStatus_Completed() when completed != null:
return completed();case BridgeAcpCompactionStatus_Failed() when failed != null:
return failed();case BridgeAcpCompactionStatus_Cancelled() when cancelled != null:
return cancelled();case BridgeAcpCompactionStatus_Other() when other != null:
return other(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpCompactionStatus_InProgress extends BridgeAcpCompactionStatus {
  const BridgeAcpCompactionStatus_InProgress(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpCompactionStatus_InProgress);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpCompactionStatus.inProgress()';
}


}




/// @nodoc


class BridgeAcpCompactionStatus_Completed extends BridgeAcpCompactionStatus {
  const BridgeAcpCompactionStatus_Completed(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpCompactionStatus_Completed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpCompactionStatus.completed()';
}


}




/// @nodoc


class BridgeAcpCompactionStatus_Failed extends BridgeAcpCompactionStatus {
  const BridgeAcpCompactionStatus_Failed(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpCompactionStatus_Failed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpCompactionStatus.failed()';
}


}




/// @nodoc


class BridgeAcpCompactionStatus_Cancelled extends BridgeAcpCompactionStatus {
  const BridgeAcpCompactionStatus_Cancelled(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpCompactionStatus_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpCompactionStatus.cancelled()';
}


}




/// @nodoc


class BridgeAcpCompactionStatus_Other extends BridgeAcpCompactionStatus {
  const BridgeAcpCompactionStatus_Other({required this.value}): super._();


 final  String value;

/// Create a copy of BridgeAcpCompactionStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpCompactionStatus_OtherCopyWith<BridgeAcpCompactionStatus_Other> get copyWith => _$BridgeAcpCompactionStatus_OtherCopyWithImpl<BridgeAcpCompactionStatus_Other>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpCompactionStatus_Other&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpCompactionStatus.other(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpCompactionStatus_OtherCopyWith<$Res> implements $BridgeAcpCompactionStatusCopyWith<$Res> {
  factory $BridgeAcpCompactionStatus_OtherCopyWith(BridgeAcpCompactionStatus_Other value, $Res Function(BridgeAcpCompactionStatus_Other) _then) = _$BridgeAcpCompactionStatus_OtherCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$BridgeAcpCompactionStatus_OtherCopyWithImpl<$Res>
    implements $BridgeAcpCompactionStatus_OtherCopyWith<$Res> {
  _$BridgeAcpCompactionStatus_OtherCopyWithImpl(this._self, this._then);

  final BridgeAcpCompactionStatus_Other _self;
  final $Res Function(BridgeAcpCompactionStatus_Other) _then;

/// Create a copy of BridgeAcpCompactionStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpCompactionStatus_Other(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpContentField {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpContentField);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpContentField()';
}


}

/// @nodoc
class $BridgeAcpContentFieldCopyWith<$Res>  {
$BridgeAcpContentFieldCopyWith(BridgeAcpContentField _, $Res Function(BridgeAcpContentField) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpContentField].
extension BridgeAcpContentFieldPatterns on BridgeAcpContentField {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpContentField_Undefined value)?  undefined,TResult Function( BridgeAcpContentField_Null value)?  null_,TResult Function( BridgeAcpContentField_Value value)?  value,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpContentField_Undefined() when undefined != null:
return undefined(_that);case BridgeAcpContentField_Null() when null_ != null:
return null_(_that);case BridgeAcpContentField_Value() when value != null:
return value(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpContentField_Undefined value)  undefined,required TResult Function( BridgeAcpContentField_Null value)  null_,required TResult Function( BridgeAcpContentField_Value value)  value,}){
final _that = this;
switch (_that) {
case BridgeAcpContentField_Undefined():
return undefined(_that);case BridgeAcpContentField_Null():
return null_(_that);case BridgeAcpContentField_Value():
return value(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpContentField_Undefined value)?  undefined,TResult? Function( BridgeAcpContentField_Null value)?  null_,TResult? Function( BridgeAcpContentField_Value value)?  value,}){
final _that = this;
switch (_that) {
case BridgeAcpContentField_Undefined() when undefined != null:
return undefined(_that);case BridgeAcpContentField_Null() when null_ != null:
return null_(_that);case BridgeAcpContentField_Value() when value != null:
return value(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  undefined,TResult Function()?  null_,TResult Function( List<BridgeAcpContentBlock> value)?  value,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpContentField_Undefined() when undefined != null:
return undefined();case BridgeAcpContentField_Null() when null_ != null:
return null_();case BridgeAcpContentField_Value() when value != null:
return value(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  undefined,required TResult Function()  null_,required TResult Function( List<BridgeAcpContentBlock> value)  value,}) {final _that = this;
switch (_that) {
case BridgeAcpContentField_Undefined():
return undefined();case BridgeAcpContentField_Null():
return null_();case BridgeAcpContentField_Value():
return value(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  undefined,TResult? Function()?  null_,TResult? Function( List<BridgeAcpContentBlock> value)?  value,}) {final _that = this;
switch (_that) {
case BridgeAcpContentField_Undefined() when undefined != null:
return undefined();case BridgeAcpContentField_Null() when null_ != null:
return null_();case BridgeAcpContentField_Value() when value != null:
return value(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpContentField_Undefined extends BridgeAcpContentField {
  const BridgeAcpContentField_Undefined(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpContentField_Undefined);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpContentField.undefined()';
}


}




/// @nodoc


class BridgeAcpContentField_Null extends BridgeAcpContentField {
  const BridgeAcpContentField_Null(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpContentField_Null);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpContentField.null_()';
}


}




/// @nodoc


class BridgeAcpContentField_Value extends BridgeAcpContentField {
  const BridgeAcpContentField_Value({required  List<BridgeAcpContentBlock> value}): _value = value,super._();


 final  List<BridgeAcpContentBlock> _value;
 List<BridgeAcpContentBlock> get value {
  if (_value is EqualUnmodifiableListView) return _value;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_value);
}


/// Create a copy of BridgeAcpContentField
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpContentField_ValueCopyWith<BridgeAcpContentField_Value> get copyWith => _$BridgeAcpContentField_ValueCopyWithImpl<BridgeAcpContentField_Value>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpContentField_Value&&const DeepCollectionEquality().equals(other.value, _value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_value));
}

@override
String toString() {
    return 'BridgeAcpContentField.value(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpContentField_ValueCopyWith<$Res> implements $BridgeAcpContentFieldCopyWith<$Res> {
  factory $BridgeAcpContentField_ValueCopyWith(BridgeAcpContentField_Value value, $Res Function(BridgeAcpContentField_Value) _then) = _$BridgeAcpContentField_ValueCopyWithImpl;
@useResult
$Res call({
 List<BridgeAcpContentBlock> value
});




}
/// @nodoc
class _$BridgeAcpContentField_ValueCopyWithImpl<$Res>
    implements $BridgeAcpContentField_ValueCopyWith<$Res> {
  _$BridgeAcpContentField_ValueCopyWithImpl(this._self, this._then);

  final BridgeAcpContentField_Value _self;
  final $Res Function(BridgeAcpContentField_Value) _then;

/// Create a copy of BridgeAcpContentField
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpContentField_Value(
value: null == value ? _self._value : value // ignore: cast_nullable_to_non_nullable
as List<BridgeAcpContentBlock>,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpMetaField {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpMetaField);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpMetaField()';
}


}

/// @nodoc
class $BridgeAcpMetaFieldCopyWith<$Res>  {
$BridgeAcpMetaFieldCopyWith(BridgeAcpMetaField _, $Res Function(BridgeAcpMetaField) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpMetaField].
extension BridgeAcpMetaFieldPatterns on BridgeAcpMetaField {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpMetaField_Undefined value)?  undefined,TResult Function( BridgeAcpMetaField_Null value)?  null_,TResult Function( BridgeAcpMetaField_Value value)?  value,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpMetaField_Undefined() when undefined != null:
return undefined(_that);case BridgeAcpMetaField_Null() when null_ != null:
return null_(_that);case BridgeAcpMetaField_Value() when value != null:
return value(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpMetaField_Undefined value)  undefined,required TResult Function( BridgeAcpMetaField_Null value)  null_,required TResult Function( BridgeAcpMetaField_Value value)  value,}){
final _that = this;
switch (_that) {
case BridgeAcpMetaField_Undefined():
return undefined(_that);case BridgeAcpMetaField_Null():
return null_(_that);case BridgeAcpMetaField_Value():
return value(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpMetaField_Undefined value)?  undefined,TResult? Function( BridgeAcpMetaField_Null value)?  null_,TResult? Function( BridgeAcpMetaField_Value value)?  value,}){
final _that = this;
switch (_that) {
case BridgeAcpMetaField_Undefined() when undefined != null:
return undefined(_that);case BridgeAcpMetaField_Null() when null_ != null:
return null_(_that);case BridgeAcpMetaField_Value() when value != null:
return value(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  undefined,TResult Function()?  null_,TResult Function( Map<String, BridgeAcpJsonValue> value)?  value,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpMetaField_Undefined() when undefined != null:
return undefined();case BridgeAcpMetaField_Null() when null_ != null:
return null_();case BridgeAcpMetaField_Value() when value != null:
return value(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  undefined,required TResult Function()  null_,required TResult Function( Map<String, BridgeAcpJsonValue> value)  value,}) {final _that = this;
switch (_that) {
case BridgeAcpMetaField_Undefined():
return undefined();case BridgeAcpMetaField_Null():
return null_();case BridgeAcpMetaField_Value():
return value(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  undefined,TResult? Function()?  null_,TResult? Function( Map<String, BridgeAcpJsonValue> value)?  value,}) {final _that = this;
switch (_that) {
case BridgeAcpMetaField_Undefined() when undefined != null:
return undefined();case BridgeAcpMetaField_Null() when null_ != null:
return null_();case BridgeAcpMetaField_Value() when value != null:
return value(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpMetaField_Undefined extends BridgeAcpMetaField {
  const BridgeAcpMetaField_Undefined(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpMetaField_Undefined);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpMetaField.undefined()';
}


}




/// @nodoc


class BridgeAcpMetaField_Null extends BridgeAcpMetaField {
  const BridgeAcpMetaField_Null(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpMetaField_Null);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpMetaField.null_()';
}


}




/// @nodoc


class BridgeAcpMetaField_Value extends BridgeAcpMetaField {
  const BridgeAcpMetaField_Value({required  Map<String, BridgeAcpJsonValue> value}): _value = value,super._();


 final  Map<String, BridgeAcpJsonValue> _value;
 Map<String, BridgeAcpJsonValue> get value {
  if (_value is EqualUnmodifiableMapView) return _value;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_value);
}


/// Create a copy of BridgeAcpMetaField
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpMetaField_ValueCopyWith<BridgeAcpMetaField_Value> get copyWith => _$BridgeAcpMetaField_ValueCopyWithImpl<BridgeAcpMetaField_Value>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpMetaField_Value&&const DeepCollectionEquality().equals(other.value, _value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_value));
}

@override
String toString() {
    return 'BridgeAcpMetaField.value(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpMetaField_ValueCopyWith<$Res> implements $BridgeAcpMetaFieldCopyWith<$Res> {
  factory $BridgeAcpMetaField_ValueCopyWith(BridgeAcpMetaField_Value value, $Res Function(BridgeAcpMetaField_Value) _then) = _$BridgeAcpMetaField_ValueCopyWithImpl;
@useResult
$Res call({
 Map<String, BridgeAcpJsonValue> value
});




}
/// @nodoc
class _$BridgeAcpMetaField_ValueCopyWithImpl<$Res>
    implements $BridgeAcpMetaField_ValueCopyWith<$Res> {
  _$BridgeAcpMetaField_ValueCopyWithImpl(this._self, this._then);

  final BridgeAcpMetaField_Value _self;
  final $Res Function(BridgeAcpMetaField_Value) _then;

/// Create a copy of BridgeAcpMetaField
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpMetaField_Value(
value: null == value ? _self._value : value // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpNoticeSeverity {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpNoticeSeverity);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpNoticeSeverity()';
}


}

/// @nodoc
class $BridgeAcpNoticeSeverityCopyWith<$Res>  {
$BridgeAcpNoticeSeverityCopyWith(BridgeAcpNoticeSeverity _, $Res Function(BridgeAcpNoticeSeverity) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpNoticeSeverity].
extension BridgeAcpNoticeSeverityPatterns on BridgeAcpNoticeSeverity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpNoticeSeverity_Info value)?  info,TResult Function( BridgeAcpNoticeSeverity_Warning value)?  warning,TResult Function( BridgeAcpNoticeSeverity_Error value)?  error,TResult Function( BridgeAcpNoticeSeverity_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpNoticeSeverity_Info() when info != null:
return info(_that);case BridgeAcpNoticeSeverity_Warning() when warning != null:
return warning(_that);case BridgeAcpNoticeSeverity_Error() when error != null:
return error(_that);case BridgeAcpNoticeSeverity_Other() when other != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpNoticeSeverity_Info value)  info,required TResult Function( BridgeAcpNoticeSeverity_Warning value)  warning,required TResult Function( BridgeAcpNoticeSeverity_Error value)  error,required TResult Function( BridgeAcpNoticeSeverity_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeAcpNoticeSeverity_Info():
return info(_that);case BridgeAcpNoticeSeverity_Warning():
return warning(_that);case BridgeAcpNoticeSeverity_Error():
return error(_that);case BridgeAcpNoticeSeverity_Other():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpNoticeSeverity_Info value)?  info,TResult? Function( BridgeAcpNoticeSeverity_Warning value)?  warning,TResult? Function( BridgeAcpNoticeSeverity_Error value)?  error,TResult? Function( BridgeAcpNoticeSeverity_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeAcpNoticeSeverity_Info() when info != null:
return info(_that);case BridgeAcpNoticeSeverity_Warning() when warning != null:
return warning(_that);case BridgeAcpNoticeSeverity_Error() when error != null:
return error(_that);case BridgeAcpNoticeSeverity_Other() when other != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  info,TResult Function()?  warning,TResult Function()?  error,TResult Function( String value)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpNoticeSeverity_Info() when info != null:
return info();case BridgeAcpNoticeSeverity_Warning() when warning != null:
return warning();case BridgeAcpNoticeSeverity_Error() when error != null:
return error();case BridgeAcpNoticeSeverity_Other() when other != null:
return other(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  info,required TResult Function()  warning,required TResult Function()  error,required TResult Function( String value)  other,}) {final _that = this;
switch (_that) {
case BridgeAcpNoticeSeverity_Info():
return info();case BridgeAcpNoticeSeverity_Warning():
return warning();case BridgeAcpNoticeSeverity_Error():
return error();case BridgeAcpNoticeSeverity_Other():
return other(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  info,TResult? Function()?  warning,TResult? Function()?  error,TResult? Function( String value)?  other,}) {final _that = this;
switch (_that) {
case BridgeAcpNoticeSeverity_Info() when info != null:
return info();case BridgeAcpNoticeSeverity_Warning() when warning != null:
return warning();case BridgeAcpNoticeSeverity_Error() when error != null:
return error();case BridgeAcpNoticeSeverity_Other() when other != null:
return other(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpNoticeSeverity_Info extends BridgeAcpNoticeSeverity {
  const BridgeAcpNoticeSeverity_Info(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpNoticeSeverity_Info);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpNoticeSeverity.info()';
}


}




/// @nodoc


class BridgeAcpNoticeSeverity_Warning extends BridgeAcpNoticeSeverity {
  const BridgeAcpNoticeSeverity_Warning(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpNoticeSeverity_Warning);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpNoticeSeverity.warning()';
}


}




/// @nodoc


class BridgeAcpNoticeSeverity_Error extends BridgeAcpNoticeSeverity {
  const BridgeAcpNoticeSeverity_Error(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpNoticeSeverity_Error);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpNoticeSeverity.error()';
}


}




/// @nodoc


class BridgeAcpNoticeSeverity_Other extends BridgeAcpNoticeSeverity {
  const BridgeAcpNoticeSeverity_Other({required this.value}): super._();


 final  String value;

/// Create a copy of BridgeAcpNoticeSeverity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpNoticeSeverity_OtherCopyWith<BridgeAcpNoticeSeverity_Other> get copyWith => _$BridgeAcpNoticeSeverity_OtherCopyWithImpl<BridgeAcpNoticeSeverity_Other>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpNoticeSeverity_Other&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpNoticeSeverity.other(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpNoticeSeverity_OtherCopyWith<$Res> implements $BridgeAcpNoticeSeverityCopyWith<$Res> {
  factory $BridgeAcpNoticeSeverity_OtherCopyWith(BridgeAcpNoticeSeverity_Other value, $Res Function(BridgeAcpNoticeSeverity_Other) _then) = _$BridgeAcpNoticeSeverity_OtherCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$BridgeAcpNoticeSeverity_OtherCopyWithImpl<$Res>
    implements $BridgeAcpNoticeSeverity_OtherCopyWith<$Res> {
  _$BridgeAcpNoticeSeverity_OtherCopyWithImpl(this._self, this._then);

  final BridgeAcpNoticeSeverity_Other _self;
  final $Res Function(BridgeAcpNoticeSeverity_Other) _then;

/// Create a copy of BridgeAcpNoticeSeverity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpNoticeSeverity_Other(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpSessionUpdate {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpSessionUpdate()';
}


}

/// @nodoc
class $BridgeAcpSessionUpdateCopyWith<$Res>  {
$BridgeAcpSessionUpdateCopyWith(BridgeAcpSessionUpdate _, $Res Function(BridgeAcpSessionUpdate) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpSessionUpdate].
extension BridgeAcpSessionUpdatePatterns on BridgeAcpSessionUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpSessionUpdate_UserMessageChunk value)?  userMessageChunk,TResult Function( BridgeAcpSessionUpdate_AgentMessageChunk value)?  agentMessageChunk,TResult Function( BridgeAcpSessionUpdate_AgentThoughtChunk value)?  agentThoughtChunk,TResult Function( BridgeAcpSessionUpdate_ToolCall value)?  toolCall,TResult Function( BridgeAcpSessionUpdate_ToolCallUpdate value)?  toolCallUpdate,TResult Function( BridgeAcpSessionUpdate_Plan value)?  plan,TResult Function( BridgeAcpSessionUpdate_AvailableCommands value)?  availableCommands,TResult Function( BridgeAcpSessionUpdate_CurrentMode value)?  currentMode,TResult Function( BridgeAcpSessionUpdate_ConfigOptions value)?  configOptions,TResult Function( BridgeAcpSessionUpdate_SessionInfo value)?  sessionInfo,TResult Function( BridgeAcpSessionUpdate_Usage value)?  usage,TResult Function( BridgeAcpSessionUpdate_Notice value)?  notice,TResult Function( BridgeAcpSessionUpdate_Compaction value)?  compaction,TResult Function( BridgeAcpSessionUpdate_CompactionSummary value)?  compactionSummary,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpSessionUpdate_UserMessageChunk() when userMessageChunk != null:
return userMessageChunk(_that);case BridgeAcpSessionUpdate_AgentMessageChunk() when agentMessageChunk != null:
return agentMessageChunk(_that);case BridgeAcpSessionUpdate_AgentThoughtChunk() when agentThoughtChunk != null:
return agentThoughtChunk(_that);case BridgeAcpSessionUpdate_ToolCall() when toolCall != null:
return toolCall(_that);case BridgeAcpSessionUpdate_ToolCallUpdate() when toolCallUpdate != null:
return toolCallUpdate(_that);case BridgeAcpSessionUpdate_Plan() when plan != null:
return plan(_that);case BridgeAcpSessionUpdate_AvailableCommands() when availableCommands != null:
return availableCommands(_that);case BridgeAcpSessionUpdate_CurrentMode() when currentMode != null:
return currentMode(_that);case BridgeAcpSessionUpdate_ConfigOptions() when configOptions != null:
return configOptions(_that);case BridgeAcpSessionUpdate_SessionInfo() when sessionInfo != null:
return sessionInfo(_that);case BridgeAcpSessionUpdate_Usage() when usage != null:
return usage(_that);case BridgeAcpSessionUpdate_Notice() when notice != null:
return notice(_that);case BridgeAcpSessionUpdate_Compaction() when compaction != null:
return compaction(_that);case BridgeAcpSessionUpdate_CompactionSummary() when compactionSummary != null:
return compactionSummary(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpSessionUpdate_UserMessageChunk value)  userMessageChunk,required TResult Function( BridgeAcpSessionUpdate_AgentMessageChunk value)  agentMessageChunk,required TResult Function( BridgeAcpSessionUpdate_AgentThoughtChunk value)  agentThoughtChunk,required TResult Function( BridgeAcpSessionUpdate_ToolCall value)  toolCall,required TResult Function( BridgeAcpSessionUpdate_ToolCallUpdate value)  toolCallUpdate,required TResult Function( BridgeAcpSessionUpdate_Plan value)  plan,required TResult Function( BridgeAcpSessionUpdate_AvailableCommands value)  availableCommands,required TResult Function( BridgeAcpSessionUpdate_CurrentMode value)  currentMode,required TResult Function( BridgeAcpSessionUpdate_ConfigOptions value)  configOptions,required TResult Function( BridgeAcpSessionUpdate_SessionInfo value)  sessionInfo,required TResult Function( BridgeAcpSessionUpdate_Usage value)  usage,required TResult Function( BridgeAcpSessionUpdate_Notice value)  notice,required TResult Function( BridgeAcpSessionUpdate_Compaction value)  compaction,required TResult Function( BridgeAcpSessionUpdate_CompactionSummary value)  compactionSummary,}){
final _that = this;
switch (_that) {
case BridgeAcpSessionUpdate_UserMessageChunk():
return userMessageChunk(_that);case BridgeAcpSessionUpdate_AgentMessageChunk():
return agentMessageChunk(_that);case BridgeAcpSessionUpdate_AgentThoughtChunk():
return agentThoughtChunk(_that);case BridgeAcpSessionUpdate_ToolCall():
return toolCall(_that);case BridgeAcpSessionUpdate_ToolCallUpdate():
return toolCallUpdate(_that);case BridgeAcpSessionUpdate_Plan():
return plan(_that);case BridgeAcpSessionUpdate_AvailableCommands():
return availableCommands(_that);case BridgeAcpSessionUpdate_CurrentMode():
return currentMode(_that);case BridgeAcpSessionUpdate_ConfigOptions():
return configOptions(_that);case BridgeAcpSessionUpdate_SessionInfo():
return sessionInfo(_that);case BridgeAcpSessionUpdate_Usage():
return usage(_that);case BridgeAcpSessionUpdate_Notice():
return notice(_that);case BridgeAcpSessionUpdate_Compaction():
return compaction(_that);case BridgeAcpSessionUpdate_CompactionSummary():
return compactionSummary(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpSessionUpdate_UserMessageChunk value)?  userMessageChunk,TResult? Function( BridgeAcpSessionUpdate_AgentMessageChunk value)?  agentMessageChunk,TResult? Function( BridgeAcpSessionUpdate_AgentThoughtChunk value)?  agentThoughtChunk,TResult? Function( BridgeAcpSessionUpdate_ToolCall value)?  toolCall,TResult? Function( BridgeAcpSessionUpdate_ToolCallUpdate value)?  toolCallUpdate,TResult? Function( BridgeAcpSessionUpdate_Plan value)?  plan,TResult? Function( BridgeAcpSessionUpdate_AvailableCommands value)?  availableCommands,TResult? Function( BridgeAcpSessionUpdate_CurrentMode value)?  currentMode,TResult? Function( BridgeAcpSessionUpdate_ConfigOptions value)?  configOptions,TResult? Function( BridgeAcpSessionUpdate_SessionInfo value)?  sessionInfo,TResult? Function( BridgeAcpSessionUpdate_Usage value)?  usage,TResult? Function( BridgeAcpSessionUpdate_Notice value)?  notice,TResult? Function( BridgeAcpSessionUpdate_Compaction value)?  compaction,TResult? Function( BridgeAcpSessionUpdate_CompactionSummary value)?  compactionSummary,}){
final _that = this;
switch (_that) {
case BridgeAcpSessionUpdate_UserMessageChunk() when userMessageChunk != null:
return userMessageChunk(_that);case BridgeAcpSessionUpdate_AgentMessageChunk() when agentMessageChunk != null:
return agentMessageChunk(_that);case BridgeAcpSessionUpdate_AgentThoughtChunk() when agentThoughtChunk != null:
return agentThoughtChunk(_that);case BridgeAcpSessionUpdate_ToolCall() when toolCall != null:
return toolCall(_that);case BridgeAcpSessionUpdate_ToolCallUpdate() when toolCallUpdate != null:
return toolCallUpdate(_that);case BridgeAcpSessionUpdate_Plan() when plan != null:
return plan(_that);case BridgeAcpSessionUpdate_AvailableCommands() when availableCommands != null:
return availableCommands(_that);case BridgeAcpSessionUpdate_CurrentMode() when currentMode != null:
return currentMode(_that);case BridgeAcpSessionUpdate_ConfigOptions() when configOptions != null:
return configOptions(_that);case BridgeAcpSessionUpdate_SessionInfo() when sessionInfo != null:
return sessionInfo(_that);case BridgeAcpSessionUpdate_Usage() when usage != null:
return usage(_that);case BridgeAcpSessionUpdate_Notice() when notice != null:
return notice(_that);case BridgeAcpSessionUpdate_Compaction() when compaction != null:
return compaction(_that);case BridgeAcpSessionUpdate_CompactionSummary() when compactionSummary != null:
return compactionSummary(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAcpContentChunk chunk)?  userMessageChunk,TResult Function( BridgeAcpContentChunk chunk)?  agentMessageChunk,TResult Function( BridgeAcpContentChunk chunk)?  agentThoughtChunk,TResult Function( BridgeAcpToolCall call)?  toolCall,TResult Function( BridgeAcpToolCallUpdate update)?  toolCallUpdate,TResult Function( List<BridgeAcpPlanEntry> entries,  Map<String, BridgeAcpJsonValue>? meta)?  plan,TResult Function( List<BridgeAcpAvailableCommand> commands,  Map<String, BridgeAcpJsonValue>? meta)?  availableCommands,TResult Function( BridgeAcpModeId modeId,  Map<String, BridgeAcpJsonValue>? meta)?  currentMode,TResult Function( List<BridgeAcpConfigOption> configOptions,  Map<String, BridgeAcpJsonValue>? meta)?  configOptions,TResult Function( BridgeAcpStringField title,  BridgeAcpStringField updatedAt,  Map<String, BridgeAcpJsonValue>? meta)?  sessionInfo,TResult Function( BigInt used,  BigInt size,  BridgeAcpCost? cost,  Map<String, BridgeAcpJsonValue>? meta)?  usage,TResult Function( BridgeAcpNoticeSeverity severity,  String title,  String? description,  Map<String, BridgeAcpJsonValue>? meta)?  notice,TResult Function( String compactionId,  BridgeAcpCompactionStatus status,  BridgeAcpContentField summary,  BridgeAcpStringField error,  BridgeAcpMetaField meta)?  compaction,TResult Function( String compactionId,  BridgeAcpContentBlock content,  Map<String, BridgeAcpJsonValue>? meta)?  compactionSummary,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpSessionUpdate_UserMessageChunk() when userMessageChunk != null:
return userMessageChunk(_that.chunk);case BridgeAcpSessionUpdate_AgentMessageChunk() when agentMessageChunk != null:
return agentMessageChunk(_that.chunk);case BridgeAcpSessionUpdate_AgentThoughtChunk() when agentThoughtChunk != null:
return agentThoughtChunk(_that.chunk);case BridgeAcpSessionUpdate_ToolCall() when toolCall != null:
return toolCall(_that.call);case BridgeAcpSessionUpdate_ToolCallUpdate() when toolCallUpdate != null:
return toolCallUpdate(_that.update);case BridgeAcpSessionUpdate_Plan() when plan != null:
return plan(_that.entries,_that.meta);case BridgeAcpSessionUpdate_AvailableCommands() when availableCommands != null:
return availableCommands(_that.commands,_that.meta);case BridgeAcpSessionUpdate_CurrentMode() when currentMode != null:
return currentMode(_that.modeId,_that.meta);case BridgeAcpSessionUpdate_ConfigOptions() when configOptions != null:
return configOptions(_that.configOptions,_that.meta);case BridgeAcpSessionUpdate_SessionInfo() when sessionInfo != null:
return sessionInfo(_that.title,_that.updatedAt,_that.meta);case BridgeAcpSessionUpdate_Usage() when usage != null:
return usage(_that.used,_that.size,_that.cost,_that.meta);case BridgeAcpSessionUpdate_Notice() when notice != null:
return notice(_that.severity,_that.title,_that.description,_that.meta);case BridgeAcpSessionUpdate_Compaction() when compaction != null:
return compaction(_that.compactionId,_that.status,_that.summary,_that.error,_that.meta);case BridgeAcpSessionUpdate_CompactionSummary() when compactionSummary != null:
return compactionSummary(_that.compactionId,_that.content,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAcpContentChunk chunk)  userMessageChunk,required TResult Function( BridgeAcpContentChunk chunk)  agentMessageChunk,required TResult Function( BridgeAcpContentChunk chunk)  agentThoughtChunk,required TResult Function( BridgeAcpToolCall call)  toolCall,required TResult Function( BridgeAcpToolCallUpdate update)  toolCallUpdate,required TResult Function( List<BridgeAcpPlanEntry> entries,  Map<String, BridgeAcpJsonValue>? meta)  plan,required TResult Function( List<BridgeAcpAvailableCommand> commands,  Map<String, BridgeAcpJsonValue>? meta)  availableCommands,required TResult Function( BridgeAcpModeId modeId,  Map<String, BridgeAcpJsonValue>? meta)  currentMode,required TResult Function( List<BridgeAcpConfigOption> configOptions,  Map<String, BridgeAcpJsonValue>? meta)  configOptions,required TResult Function( BridgeAcpStringField title,  BridgeAcpStringField updatedAt,  Map<String, BridgeAcpJsonValue>? meta)  sessionInfo,required TResult Function( BigInt used,  BigInt size,  BridgeAcpCost? cost,  Map<String, BridgeAcpJsonValue>? meta)  usage,required TResult Function( BridgeAcpNoticeSeverity severity,  String title,  String? description,  Map<String, BridgeAcpJsonValue>? meta)  notice,required TResult Function( String compactionId,  BridgeAcpCompactionStatus status,  BridgeAcpContentField summary,  BridgeAcpStringField error,  BridgeAcpMetaField meta)  compaction,required TResult Function( String compactionId,  BridgeAcpContentBlock content,  Map<String, BridgeAcpJsonValue>? meta)  compactionSummary,}) {final _that = this;
switch (_that) {
case BridgeAcpSessionUpdate_UserMessageChunk():
return userMessageChunk(_that.chunk);case BridgeAcpSessionUpdate_AgentMessageChunk():
return agentMessageChunk(_that.chunk);case BridgeAcpSessionUpdate_AgentThoughtChunk():
return agentThoughtChunk(_that.chunk);case BridgeAcpSessionUpdate_ToolCall():
return toolCall(_that.call);case BridgeAcpSessionUpdate_ToolCallUpdate():
return toolCallUpdate(_that.update);case BridgeAcpSessionUpdate_Plan():
return plan(_that.entries,_that.meta);case BridgeAcpSessionUpdate_AvailableCommands():
return availableCommands(_that.commands,_that.meta);case BridgeAcpSessionUpdate_CurrentMode():
return currentMode(_that.modeId,_that.meta);case BridgeAcpSessionUpdate_ConfigOptions():
return configOptions(_that.configOptions,_that.meta);case BridgeAcpSessionUpdate_SessionInfo():
return sessionInfo(_that.title,_that.updatedAt,_that.meta);case BridgeAcpSessionUpdate_Usage():
return usage(_that.used,_that.size,_that.cost,_that.meta);case BridgeAcpSessionUpdate_Notice():
return notice(_that.severity,_that.title,_that.description,_that.meta);case BridgeAcpSessionUpdate_Compaction():
return compaction(_that.compactionId,_that.status,_that.summary,_that.error,_that.meta);case BridgeAcpSessionUpdate_CompactionSummary():
return compactionSummary(_that.compactionId,_that.content,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAcpContentChunk chunk)?  userMessageChunk,TResult? Function( BridgeAcpContentChunk chunk)?  agentMessageChunk,TResult? Function( BridgeAcpContentChunk chunk)?  agentThoughtChunk,TResult? Function( BridgeAcpToolCall call)?  toolCall,TResult? Function( BridgeAcpToolCallUpdate update)?  toolCallUpdate,TResult? Function( List<BridgeAcpPlanEntry> entries,  Map<String, BridgeAcpJsonValue>? meta)?  plan,TResult? Function( List<BridgeAcpAvailableCommand> commands,  Map<String, BridgeAcpJsonValue>? meta)?  availableCommands,TResult? Function( BridgeAcpModeId modeId,  Map<String, BridgeAcpJsonValue>? meta)?  currentMode,TResult? Function( List<BridgeAcpConfigOption> configOptions,  Map<String, BridgeAcpJsonValue>? meta)?  configOptions,TResult? Function( BridgeAcpStringField title,  BridgeAcpStringField updatedAt,  Map<String, BridgeAcpJsonValue>? meta)?  sessionInfo,TResult? Function( BigInt used,  BigInt size,  BridgeAcpCost? cost,  Map<String, BridgeAcpJsonValue>? meta)?  usage,TResult? Function( BridgeAcpNoticeSeverity severity,  String title,  String? description,  Map<String, BridgeAcpJsonValue>? meta)?  notice,TResult? Function( String compactionId,  BridgeAcpCompactionStatus status,  BridgeAcpContentField summary,  BridgeAcpStringField error,  BridgeAcpMetaField meta)?  compaction,TResult? Function( String compactionId,  BridgeAcpContentBlock content,  Map<String, BridgeAcpJsonValue>? meta)?  compactionSummary,}) {final _that = this;
switch (_that) {
case BridgeAcpSessionUpdate_UserMessageChunk() when userMessageChunk != null:
return userMessageChunk(_that.chunk);case BridgeAcpSessionUpdate_AgentMessageChunk() when agentMessageChunk != null:
return agentMessageChunk(_that.chunk);case BridgeAcpSessionUpdate_AgentThoughtChunk() when agentThoughtChunk != null:
return agentThoughtChunk(_that.chunk);case BridgeAcpSessionUpdate_ToolCall() when toolCall != null:
return toolCall(_that.call);case BridgeAcpSessionUpdate_ToolCallUpdate() when toolCallUpdate != null:
return toolCallUpdate(_that.update);case BridgeAcpSessionUpdate_Plan() when plan != null:
return plan(_that.entries,_that.meta);case BridgeAcpSessionUpdate_AvailableCommands() when availableCommands != null:
return availableCommands(_that.commands,_that.meta);case BridgeAcpSessionUpdate_CurrentMode() when currentMode != null:
return currentMode(_that.modeId,_that.meta);case BridgeAcpSessionUpdate_ConfigOptions() when configOptions != null:
return configOptions(_that.configOptions,_that.meta);case BridgeAcpSessionUpdate_SessionInfo() when sessionInfo != null:
return sessionInfo(_that.title,_that.updatedAt,_that.meta);case BridgeAcpSessionUpdate_Usage() when usage != null:
return usage(_that.used,_that.size,_that.cost,_that.meta);case BridgeAcpSessionUpdate_Notice() when notice != null:
return notice(_that.severity,_that.title,_that.description,_that.meta);case BridgeAcpSessionUpdate_Compaction() when compaction != null:
return compaction(_that.compactionId,_that.status,_that.summary,_that.error,_that.meta);case BridgeAcpSessionUpdate_CompactionSummary() when compactionSummary != null:
return compactionSummary(_that.compactionId,_that.content,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpSessionUpdate_UserMessageChunk extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_UserMessageChunk({required this.chunk}): super._();


 final  BridgeAcpContentChunk chunk;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_UserMessageChunkCopyWith<BridgeAcpSessionUpdate_UserMessageChunk> get copyWith => _$BridgeAcpSessionUpdate_UserMessageChunkCopyWithImpl<BridgeAcpSessionUpdate_UserMessageChunk>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_UserMessageChunk&&(identical(other.chunk, chunk) || other.chunk == chunk));
}


@override
int get hashCode {
    return Object.hash(runtimeType,chunk);
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.userMessageChunk(chunk: $chunk)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_UserMessageChunkCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_UserMessageChunkCopyWith(BridgeAcpSessionUpdate_UserMessageChunk value, $Res Function(BridgeAcpSessionUpdate_UserMessageChunk) _then) = _$BridgeAcpSessionUpdate_UserMessageChunkCopyWithImpl;
@useResult
$Res call({
 BridgeAcpContentChunk chunk
});




}
/// @nodoc
class _$BridgeAcpSessionUpdate_UserMessageChunkCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_UserMessageChunkCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_UserMessageChunkCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_UserMessageChunk _self;
  final $Res Function(BridgeAcpSessionUpdate_UserMessageChunk) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? chunk = null,}) {
  return _then(BridgeAcpSessionUpdate_UserMessageChunk(
chunk: null == chunk ? _self.chunk : chunk // ignore: cast_nullable_to_non_nullable
as BridgeAcpContentChunk,
  ));
}


}

/// @nodoc


class BridgeAcpSessionUpdate_AgentMessageChunk extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_AgentMessageChunk({required this.chunk}): super._();


 final  BridgeAcpContentChunk chunk;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_AgentMessageChunkCopyWith<BridgeAcpSessionUpdate_AgentMessageChunk> get copyWith => _$BridgeAcpSessionUpdate_AgentMessageChunkCopyWithImpl<BridgeAcpSessionUpdate_AgentMessageChunk>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_AgentMessageChunk&&(identical(other.chunk, chunk) || other.chunk == chunk));
}


@override
int get hashCode {
    return Object.hash(runtimeType,chunk);
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.agentMessageChunk(chunk: $chunk)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_AgentMessageChunkCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_AgentMessageChunkCopyWith(BridgeAcpSessionUpdate_AgentMessageChunk value, $Res Function(BridgeAcpSessionUpdate_AgentMessageChunk) _then) = _$BridgeAcpSessionUpdate_AgentMessageChunkCopyWithImpl;
@useResult
$Res call({
 BridgeAcpContentChunk chunk
});




}
/// @nodoc
class _$BridgeAcpSessionUpdate_AgentMessageChunkCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_AgentMessageChunkCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_AgentMessageChunkCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_AgentMessageChunk _self;
  final $Res Function(BridgeAcpSessionUpdate_AgentMessageChunk) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? chunk = null,}) {
  return _then(BridgeAcpSessionUpdate_AgentMessageChunk(
chunk: null == chunk ? _self.chunk : chunk // ignore: cast_nullable_to_non_nullable
as BridgeAcpContentChunk,
  ));
}


}

/// @nodoc


class BridgeAcpSessionUpdate_AgentThoughtChunk extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_AgentThoughtChunk({required this.chunk}): super._();


 final  BridgeAcpContentChunk chunk;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_AgentThoughtChunkCopyWith<BridgeAcpSessionUpdate_AgentThoughtChunk> get copyWith => _$BridgeAcpSessionUpdate_AgentThoughtChunkCopyWithImpl<BridgeAcpSessionUpdate_AgentThoughtChunk>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_AgentThoughtChunk&&(identical(other.chunk, chunk) || other.chunk == chunk));
}


@override
int get hashCode {
    return Object.hash(runtimeType,chunk);
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.agentThoughtChunk(chunk: $chunk)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_AgentThoughtChunkCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_AgentThoughtChunkCopyWith(BridgeAcpSessionUpdate_AgentThoughtChunk value, $Res Function(BridgeAcpSessionUpdate_AgentThoughtChunk) _then) = _$BridgeAcpSessionUpdate_AgentThoughtChunkCopyWithImpl;
@useResult
$Res call({
 BridgeAcpContentChunk chunk
});




}
/// @nodoc
class _$BridgeAcpSessionUpdate_AgentThoughtChunkCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_AgentThoughtChunkCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_AgentThoughtChunkCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_AgentThoughtChunk _self;
  final $Res Function(BridgeAcpSessionUpdate_AgentThoughtChunk) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? chunk = null,}) {
  return _then(BridgeAcpSessionUpdate_AgentThoughtChunk(
chunk: null == chunk ? _self.chunk : chunk // ignore: cast_nullable_to_non_nullable
as BridgeAcpContentChunk,
  ));
}


}

/// @nodoc


class BridgeAcpSessionUpdate_ToolCall extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_ToolCall({required this.call}): super._();


 final  BridgeAcpToolCall call;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_ToolCallCopyWith<BridgeAcpSessionUpdate_ToolCall> get copyWith => _$BridgeAcpSessionUpdate_ToolCallCopyWithImpl<BridgeAcpSessionUpdate_ToolCall>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_ToolCall&&(identical(other.call, call) || other.call == call));
}


@override
int get hashCode {
    return Object.hash(runtimeType,call);
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.toolCall(call: $call)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_ToolCallCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_ToolCallCopyWith(BridgeAcpSessionUpdate_ToolCall value, $Res Function(BridgeAcpSessionUpdate_ToolCall) _then) = _$BridgeAcpSessionUpdate_ToolCallCopyWithImpl;
@useResult
$Res call({
 BridgeAcpToolCall call
});




}
/// @nodoc
class _$BridgeAcpSessionUpdate_ToolCallCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_ToolCallCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_ToolCallCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_ToolCall _self;
  final $Res Function(BridgeAcpSessionUpdate_ToolCall) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? call = null,}) {
  return _then(BridgeAcpSessionUpdate_ToolCall(
call: null == call ? _self.call : call // ignore: cast_nullable_to_non_nullable
as BridgeAcpToolCall,
  ));
}


}

/// @nodoc


class BridgeAcpSessionUpdate_ToolCallUpdate extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_ToolCallUpdate({required this.update}): super._();


 final  BridgeAcpToolCallUpdate update;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_ToolCallUpdateCopyWith<BridgeAcpSessionUpdate_ToolCallUpdate> get copyWith => _$BridgeAcpSessionUpdate_ToolCallUpdateCopyWithImpl<BridgeAcpSessionUpdate_ToolCallUpdate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_ToolCallUpdate&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,update);
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.toolCallUpdate(update: $update)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_ToolCallUpdateCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_ToolCallUpdateCopyWith(BridgeAcpSessionUpdate_ToolCallUpdate value, $Res Function(BridgeAcpSessionUpdate_ToolCallUpdate) _then) = _$BridgeAcpSessionUpdate_ToolCallUpdateCopyWithImpl;
@useResult
$Res call({
 BridgeAcpToolCallUpdate update
});




}
/// @nodoc
class _$BridgeAcpSessionUpdate_ToolCallUpdateCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_ToolCallUpdateCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_ToolCallUpdateCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_ToolCallUpdate _self;
  final $Res Function(BridgeAcpSessionUpdate_ToolCallUpdate) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? update = null,}) {
  return _then(BridgeAcpSessionUpdate_ToolCallUpdate(
update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as BridgeAcpToolCallUpdate,
  ));
}


}

/// @nodoc


class BridgeAcpSessionUpdate_Plan extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_Plan({required  List<BridgeAcpPlanEntry> entries,  Map<String, BridgeAcpJsonValue>? meta}): _entries = entries,_meta = meta,super._();


 final  List<BridgeAcpPlanEntry> _entries;
 List<BridgeAcpPlanEntry> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}

 final  Map<String, BridgeAcpJsonValue>? _meta;
 Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_PlanCopyWith<BridgeAcpSessionUpdate_Plan> get copyWith => _$BridgeAcpSessionUpdate_PlanCopyWithImpl<BridgeAcpSessionUpdate_Plan>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_Plan&&const DeepCollectionEquality().equals(other.entries, _entries)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_entries),const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.plan(entries: $entries, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_PlanCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_PlanCopyWith(BridgeAcpSessionUpdate_Plan value, $Res Function(BridgeAcpSessionUpdate_Plan) _then) = _$BridgeAcpSessionUpdate_PlanCopyWithImpl;
@useResult
$Res call({
 List<BridgeAcpPlanEntry> entries, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpSessionUpdate_PlanCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_PlanCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_PlanCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_Plan _self;
  final $Res Function(BridgeAcpSessionUpdate_Plan) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? entries = null,Object? meta = freezed,}) {
  return _then(BridgeAcpSessionUpdate_Plan(
entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<BridgeAcpPlanEntry>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpSessionUpdate_AvailableCommands extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_AvailableCommands({required  List<BridgeAcpAvailableCommand> commands,  Map<String, BridgeAcpJsonValue>? meta}): _commands = commands,_meta = meta,super._();


 final  List<BridgeAcpAvailableCommand> _commands;
 List<BridgeAcpAvailableCommand> get commands {
  if (_commands is EqualUnmodifiableListView) return _commands;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_commands);
}

 final  Map<String, BridgeAcpJsonValue>? _meta;
 Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_AvailableCommandsCopyWith<BridgeAcpSessionUpdate_AvailableCommands> get copyWith => _$BridgeAcpSessionUpdate_AvailableCommandsCopyWithImpl<BridgeAcpSessionUpdate_AvailableCommands>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_AvailableCommands&&const DeepCollectionEquality().equals(other.commands, _commands)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_commands),const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.availableCommands(commands: $commands, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_AvailableCommandsCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_AvailableCommandsCopyWith(BridgeAcpSessionUpdate_AvailableCommands value, $Res Function(BridgeAcpSessionUpdate_AvailableCommands) _then) = _$BridgeAcpSessionUpdate_AvailableCommandsCopyWithImpl;
@useResult
$Res call({
 List<BridgeAcpAvailableCommand> commands, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpSessionUpdate_AvailableCommandsCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_AvailableCommandsCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_AvailableCommandsCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_AvailableCommands _self;
  final $Res Function(BridgeAcpSessionUpdate_AvailableCommands) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? commands = null,Object? meta = freezed,}) {
  return _then(BridgeAcpSessionUpdate_AvailableCommands(
commands: null == commands ? _self._commands : commands // ignore: cast_nullable_to_non_nullable
as List<BridgeAcpAvailableCommand>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpSessionUpdate_CurrentMode extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_CurrentMode({required this.modeId,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  BridgeAcpModeId modeId;
 final  Map<String, BridgeAcpJsonValue>? _meta;
 Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_CurrentModeCopyWith<BridgeAcpSessionUpdate_CurrentMode> get copyWith => _$BridgeAcpSessionUpdate_CurrentModeCopyWithImpl<BridgeAcpSessionUpdate_CurrentMode>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_CurrentMode&&(identical(other.modeId, modeId) || other.modeId == modeId)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modeId,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.currentMode(modeId: $modeId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_CurrentModeCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_CurrentModeCopyWith(BridgeAcpSessionUpdate_CurrentMode value, $Res Function(BridgeAcpSessionUpdate_CurrentMode) _then) = _$BridgeAcpSessionUpdate_CurrentModeCopyWithImpl;
@useResult
$Res call({
 BridgeAcpModeId modeId, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpSessionUpdate_CurrentModeCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_CurrentModeCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_CurrentModeCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_CurrentMode _self;
  final $Res Function(BridgeAcpSessionUpdate_CurrentMode) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? modeId = null,Object? meta = freezed,}) {
  return _then(BridgeAcpSessionUpdate_CurrentMode(
modeId: null == modeId ? _self.modeId : modeId // ignore: cast_nullable_to_non_nullable
as BridgeAcpModeId,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpSessionUpdate_ConfigOptions extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_ConfigOptions({required  List<BridgeAcpConfigOption> configOptions,  Map<String, BridgeAcpJsonValue>? meta}): _configOptions = configOptions,_meta = meta,super._();


 final  List<BridgeAcpConfigOption> _configOptions;
 List<BridgeAcpConfigOption> get configOptions {
  if (_configOptions is EqualUnmodifiableListView) return _configOptions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_configOptions);
}

 final  Map<String, BridgeAcpJsonValue>? _meta;
 Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_ConfigOptionsCopyWith<BridgeAcpSessionUpdate_ConfigOptions> get copyWith => _$BridgeAcpSessionUpdate_ConfigOptionsCopyWithImpl<BridgeAcpSessionUpdate_ConfigOptions>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_ConfigOptions&&const DeepCollectionEquality().equals(other.configOptions, _configOptions)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_configOptions),const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.configOptions(configOptions: $configOptions, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_ConfigOptionsCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_ConfigOptionsCopyWith(BridgeAcpSessionUpdate_ConfigOptions value, $Res Function(BridgeAcpSessionUpdate_ConfigOptions) _then) = _$BridgeAcpSessionUpdate_ConfigOptionsCopyWithImpl;
@useResult
$Res call({
 List<BridgeAcpConfigOption> configOptions, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpSessionUpdate_ConfigOptionsCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_ConfigOptionsCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_ConfigOptionsCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_ConfigOptions _self;
  final $Res Function(BridgeAcpSessionUpdate_ConfigOptions) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? configOptions = null,Object? meta = freezed,}) {
  return _then(BridgeAcpSessionUpdate_ConfigOptions(
configOptions: null == configOptions ? _self._configOptions : configOptions // ignore: cast_nullable_to_non_nullable
as List<BridgeAcpConfigOption>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpSessionUpdate_SessionInfo extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_SessionInfo({required this.title, required this.updatedAt,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  BridgeAcpStringField title;
 final  BridgeAcpStringField updatedAt;
 final  Map<String, BridgeAcpJsonValue>? _meta;
 Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_SessionInfoCopyWith<BridgeAcpSessionUpdate_SessionInfo> get copyWith => _$BridgeAcpSessionUpdate_SessionInfoCopyWithImpl<BridgeAcpSessionUpdate_SessionInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_SessionInfo&&(identical(other.title, title) || other.title == title)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,updatedAt,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.sessionInfo(title: $title, updatedAt: $updatedAt, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_SessionInfoCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_SessionInfoCopyWith(BridgeAcpSessionUpdate_SessionInfo value, $Res Function(BridgeAcpSessionUpdate_SessionInfo) _then) = _$BridgeAcpSessionUpdate_SessionInfoCopyWithImpl;
@useResult
$Res call({
 BridgeAcpStringField title, BridgeAcpStringField updatedAt, Map<String, BridgeAcpJsonValue>? meta
});


$BridgeAcpStringFieldCopyWith<$Res> get title;$BridgeAcpStringFieldCopyWith<$Res> get updatedAt;

}
/// @nodoc
class _$BridgeAcpSessionUpdate_SessionInfoCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_SessionInfoCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_SessionInfoCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_SessionInfo _self;
  final $Res Function(BridgeAcpSessionUpdate_SessionInfo) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = null,Object? updatedAt = null,Object? meta = freezed,}) {
  return _then(BridgeAcpSessionUpdate_SessionInfo(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as BridgeAcpStringField,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as BridgeAcpStringField,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpStringFieldCopyWith<$Res> get title {

  return $BridgeAcpStringFieldCopyWith<$Res>(_self.title, (value) {
    return _then(_self.copyWith(title: value));
  });
}/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpStringFieldCopyWith<$Res> get updatedAt {

  return $BridgeAcpStringFieldCopyWith<$Res>(_self.updatedAt, (value) {
    return _then(_self.copyWith(updatedAt: value));
  });
}
}

/// @nodoc


class BridgeAcpSessionUpdate_Usage extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_Usage({required this.used, required this.size, this.cost,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  BigInt used;
 final  BigInt size;
 final  BridgeAcpCost? cost;
 final  Map<String, BridgeAcpJsonValue>? _meta;
 Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_UsageCopyWith<BridgeAcpSessionUpdate_Usage> get copyWith => _$BridgeAcpSessionUpdate_UsageCopyWithImpl<BridgeAcpSessionUpdate_Usage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_Usage&&(identical(other.used, used) || other.used == used)&&(identical(other.size, size) || other.size == size)&&(identical(other.cost, cost) || other.cost == cost)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,used,size,cost,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.usage(used: $used, size: $size, cost: $cost, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_UsageCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_UsageCopyWith(BridgeAcpSessionUpdate_Usage value, $Res Function(BridgeAcpSessionUpdate_Usage) _then) = _$BridgeAcpSessionUpdate_UsageCopyWithImpl;
@useResult
$Res call({
 BigInt used, BigInt size, BridgeAcpCost? cost, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpSessionUpdate_UsageCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_UsageCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_UsageCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_Usage _self;
  final $Res Function(BridgeAcpSessionUpdate_Usage) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? used = null,Object? size = null,Object? cost = freezed,Object? meta = freezed,}) {
  return _then(BridgeAcpSessionUpdate_Usage(
used: null == used ? _self.used : used // ignore: cast_nullable_to_non_nullable
as BigInt,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as BigInt,cost: freezed == cost ? _self.cost : cost // ignore: cast_nullable_to_non_nullable
as BridgeAcpCost?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpSessionUpdate_Notice extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_Notice({required this.severity, required this.title, this.description,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  BridgeAcpNoticeSeverity severity;
 final  String title;
 final  String? description;
 final  Map<String, BridgeAcpJsonValue>? _meta;
 Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_NoticeCopyWith<BridgeAcpSessionUpdate_Notice> get copyWith => _$BridgeAcpSessionUpdate_NoticeCopyWithImpl<BridgeAcpSessionUpdate_Notice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_Notice&&(identical(other.severity, severity) || other.severity == severity)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,severity,title,description,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.notice(severity: $severity, title: $title, description: $description, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_NoticeCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_NoticeCopyWith(BridgeAcpSessionUpdate_Notice value, $Res Function(BridgeAcpSessionUpdate_Notice) _then) = _$BridgeAcpSessionUpdate_NoticeCopyWithImpl;
@useResult
$Res call({
 BridgeAcpNoticeSeverity severity, String title, String? description, Map<String, BridgeAcpJsonValue>? meta
});


$BridgeAcpNoticeSeverityCopyWith<$Res> get severity;

}
/// @nodoc
class _$BridgeAcpSessionUpdate_NoticeCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_NoticeCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_NoticeCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_Notice _self;
  final $Res Function(BridgeAcpSessionUpdate_Notice) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? severity = null,Object? title = null,Object? description = freezed,Object? meta = freezed,}) {
  return _then(BridgeAcpSessionUpdate_Notice(
severity: null == severity ? _self.severity : severity // ignore: cast_nullable_to_non_nullable
as BridgeAcpNoticeSeverity,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpNoticeSeverityCopyWith<$Res> get severity {

  return $BridgeAcpNoticeSeverityCopyWith<$Res>(_self.severity, (value) {
    return _then(_self.copyWith(severity: value));
  });
}
}

/// @nodoc


class BridgeAcpSessionUpdate_Compaction extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_Compaction({required this.compactionId, required this.status, required this.summary, required this.error, required this.meta}): super._();


 final  String compactionId;
 final  BridgeAcpCompactionStatus status;
 final  BridgeAcpContentField summary;
 final  BridgeAcpStringField error;
 final  BridgeAcpMetaField meta;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_CompactionCopyWith<BridgeAcpSessionUpdate_Compaction> get copyWith => _$BridgeAcpSessionUpdate_CompactionCopyWithImpl<BridgeAcpSessionUpdate_Compaction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_Compaction&&(identical(other.compactionId, compactionId) || other.compactionId == compactionId)&&(identical(other.status, status) || other.status == status)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.error, error) || other.error == error)&&(identical(other.meta, meta) || other.meta == meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,compactionId,status,summary,error,meta);
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.compaction(compactionId: $compactionId, status: $status, summary: $summary, error: $error, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_CompactionCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_CompactionCopyWith(BridgeAcpSessionUpdate_Compaction value, $Res Function(BridgeAcpSessionUpdate_Compaction) _then) = _$BridgeAcpSessionUpdate_CompactionCopyWithImpl;
@useResult
$Res call({
 String compactionId, BridgeAcpCompactionStatus status, BridgeAcpContentField summary, BridgeAcpStringField error, BridgeAcpMetaField meta
});


$BridgeAcpCompactionStatusCopyWith<$Res> get status;$BridgeAcpContentFieldCopyWith<$Res> get summary;$BridgeAcpStringFieldCopyWith<$Res> get error;$BridgeAcpMetaFieldCopyWith<$Res> get meta;

}
/// @nodoc
class _$BridgeAcpSessionUpdate_CompactionCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_CompactionCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_CompactionCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_Compaction _self;
  final $Res Function(BridgeAcpSessionUpdate_Compaction) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? compactionId = null,Object? status = null,Object? summary = null,Object? error = null,Object? meta = null,}) {
  return _then(BridgeAcpSessionUpdate_Compaction(
compactionId: null == compactionId ? _self.compactionId : compactionId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BridgeAcpCompactionStatus,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as BridgeAcpContentField,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeAcpStringField,meta: null == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as BridgeAcpMetaField,
  ));
}

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpCompactionStatusCopyWith<$Res> get status {

  return $BridgeAcpCompactionStatusCopyWith<$Res>(_self.status, (value) {
    return _then(_self.copyWith(status: value));
  });
}/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpContentFieldCopyWith<$Res> get summary {

  return $BridgeAcpContentFieldCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpStringFieldCopyWith<$Res> get error {

  return $BridgeAcpStringFieldCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpMetaFieldCopyWith<$Res> get meta {

  return $BridgeAcpMetaFieldCopyWith<$Res>(_self.meta, (value) {
    return _then(_self.copyWith(meta: value));
  });
}
}

/// @nodoc


class BridgeAcpSessionUpdate_CompactionSummary extends BridgeAcpSessionUpdate {
  const BridgeAcpSessionUpdate_CompactionSummary({required this.compactionId, required this.content,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  String compactionId;
 final  BridgeAcpContentBlock content;
 final  Map<String, BridgeAcpJsonValue>? _meta;
 Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionUpdate_CompactionSummaryCopyWith<BridgeAcpSessionUpdate_CompactionSummary> get copyWith => _$BridgeAcpSessionUpdate_CompactionSummaryCopyWithImpl<BridgeAcpSessionUpdate_CompactionSummary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionUpdate_CompactionSummary&&(identical(other.compactionId, compactionId) || other.compactionId == compactionId)&&(identical(other.content, content) || other.content == content)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,compactionId,content,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpSessionUpdate.compactionSummary(compactionId: $compactionId, content: $content, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionUpdate_CompactionSummaryCopyWith<$Res> implements $BridgeAcpSessionUpdateCopyWith<$Res> {
  factory $BridgeAcpSessionUpdate_CompactionSummaryCopyWith(BridgeAcpSessionUpdate_CompactionSummary value, $Res Function(BridgeAcpSessionUpdate_CompactionSummary) _then) = _$BridgeAcpSessionUpdate_CompactionSummaryCopyWithImpl;
@useResult
$Res call({
 String compactionId, BridgeAcpContentBlock content, Map<String, BridgeAcpJsonValue>? meta
});


$BridgeAcpContentBlockCopyWith<$Res> get content;

}
/// @nodoc
class _$BridgeAcpSessionUpdate_CompactionSummaryCopyWithImpl<$Res>
    implements $BridgeAcpSessionUpdate_CompactionSummaryCopyWith<$Res> {
  _$BridgeAcpSessionUpdate_CompactionSummaryCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionUpdate_CompactionSummary _self;
  final $Res Function(BridgeAcpSessionUpdate_CompactionSummary) _then;

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? compactionId = null,Object? content = null,Object? meta = freezed,}) {
  return _then(BridgeAcpSessionUpdate_CompactionSummary(
compactionId: null == compactionId ? _self.compactionId : compactionId // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as BridgeAcpContentBlock,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}

/// Create a copy of BridgeAcpSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpContentBlockCopyWith<$Res> get content {

  return $BridgeAcpContentBlockCopyWith<$Res>(_self.content, (value) {
    return _then(_self.copyWith(content: value));
  });
}
}

/// @nodoc
mixin _$BridgeAcpStringField {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpStringField);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpStringField()';
}


}

/// @nodoc
class $BridgeAcpStringFieldCopyWith<$Res>  {
$BridgeAcpStringFieldCopyWith(BridgeAcpStringField _, $Res Function(BridgeAcpStringField) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpStringField].
extension BridgeAcpStringFieldPatterns on BridgeAcpStringField {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpStringField_Undefined value)?  undefined,TResult Function( BridgeAcpStringField_Null value)?  null_,TResult Function( BridgeAcpStringField_Value value)?  value,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpStringField_Undefined() when undefined != null:
return undefined(_that);case BridgeAcpStringField_Null() when null_ != null:
return null_(_that);case BridgeAcpStringField_Value() when value != null:
return value(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpStringField_Undefined value)  undefined,required TResult Function( BridgeAcpStringField_Null value)  null_,required TResult Function( BridgeAcpStringField_Value value)  value,}){
final _that = this;
switch (_that) {
case BridgeAcpStringField_Undefined():
return undefined(_that);case BridgeAcpStringField_Null():
return null_(_that);case BridgeAcpStringField_Value():
return value(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpStringField_Undefined value)?  undefined,TResult? Function( BridgeAcpStringField_Null value)?  null_,TResult? Function( BridgeAcpStringField_Value value)?  value,}){
final _that = this;
switch (_that) {
case BridgeAcpStringField_Undefined() when undefined != null:
return undefined(_that);case BridgeAcpStringField_Null() when null_ != null:
return null_(_that);case BridgeAcpStringField_Value() when value != null:
return value(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  undefined,TResult Function()?  null_,TResult Function( String value)?  value,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpStringField_Undefined() when undefined != null:
return undefined();case BridgeAcpStringField_Null() when null_ != null:
return null_();case BridgeAcpStringField_Value() when value != null:
return value(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  undefined,required TResult Function()  null_,required TResult Function( String value)  value,}) {final _that = this;
switch (_that) {
case BridgeAcpStringField_Undefined():
return undefined();case BridgeAcpStringField_Null():
return null_();case BridgeAcpStringField_Value():
return value(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  undefined,TResult? Function()?  null_,TResult? Function( String value)?  value,}) {final _that = this;
switch (_that) {
case BridgeAcpStringField_Undefined() when undefined != null:
return undefined();case BridgeAcpStringField_Null() when null_ != null:
return null_();case BridgeAcpStringField_Value() when value != null:
return value(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpStringField_Undefined extends BridgeAcpStringField {
  const BridgeAcpStringField_Undefined(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpStringField_Undefined);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpStringField.undefined()';
}


}




/// @nodoc


class BridgeAcpStringField_Null extends BridgeAcpStringField {
  const BridgeAcpStringField_Null(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpStringField_Null);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpStringField.null_()';
}


}




/// @nodoc


class BridgeAcpStringField_Value extends BridgeAcpStringField {
  const BridgeAcpStringField_Value({required this.value}): super._();


 final  String value;

/// Create a copy of BridgeAcpStringField
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpStringField_ValueCopyWith<BridgeAcpStringField_Value> get copyWith => _$BridgeAcpStringField_ValueCopyWithImpl<BridgeAcpStringField_Value>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpStringField_Value&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpStringField.value(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpStringField_ValueCopyWith<$Res> implements $BridgeAcpStringFieldCopyWith<$Res> {
  factory $BridgeAcpStringField_ValueCopyWith(BridgeAcpStringField_Value value, $Res Function(BridgeAcpStringField_Value) _then) = _$BridgeAcpStringField_ValueCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$BridgeAcpStringField_ValueCopyWithImpl<$Res>
    implements $BridgeAcpStringField_ValueCopyWith<$Res> {
  _$BridgeAcpStringField_ValueCopyWithImpl(this._self, this._then);

  final BridgeAcpStringField_Value _self;
  final $Res Function(BridgeAcpStringField_Value) _then;

/// Create a copy of BridgeAcpStringField
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpStringField_Value(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpToolContent {

 Map<String, BridgeAcpJsonValue>? get meta;
/// Create a copy of BridgeAcpToolContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpToolContentCopyWith<BridgeAcpToolContent> get copyWith => _$BridgeAcpToolContentCopyWithImpl<BridgeAcpToolContent>(this as BridgeAcpToolContent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAcpToolContent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpToolContent&&const DeepCollectionEquality().equals(other.meta, _this.meta));
}


@override
int get hashCode {
  final _this = this as BridgeAcpToolContent;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.meta));
}

@override
String toString() {
  final _this = this as BridgeAcpToolContent;
  return 'BridgeAcpToolContent(meta: ${_this.meta})';
}


}

/// @nodoc
abstract mixin class $BridgeAcpToolContentCopyWith<$Res>  {
  factory $BridgeAcpToolContentCopyWith(BridgeAcpToolContent value, $Res Function(BridgeAcpToolContent) _then) = _$BridgeAcpToolContentCopyWithImpl;
@useResult
$Res call({
 Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpToolContentCopyWithImpl<$Res>
    implements $BridgeAcpToolContentCopyWith<$Res> {
  _$BridgeAcpToolContentCopyWithImpl(this._self, this._then);

  final BridgeAcpToolContent _self;
  final $Res Function(BridgeAcpToolContent) _then;

/// Create a copy of BridgeAcpToolContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? meta = freezed,}) {
  return _then(_self.copyWith(
meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAcpToolContent].
extension BridgeAcpToolContentPatterns on BridgeAcpToolContent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpToolContent_Content value)?  content,TResult Function( BridgeAcpToolContent_Diff value)?  diff,TResult Function( BridgeAcpToolContent_Terminal value)?  terminal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpToolContent_Content() when content != null:
return content(_that);case BridgeAcpToolContent_Diff() when diff != null:
return diff(_that);case BridgeAcpToolContent_Terminal() when terminal != null:
return terminal(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpToolContent_Content value)  content,required TResult Function( BridgeAcpToolContent_Diff value)  diff,required TResult Function( BridgeAcpToolContent_Terminal value)  terminal,}){
final _that = this;
switch (_that) {
case BridgeAcpToolContent_Content():
return content(_that);case BridgeAcpToolContent_Diff():
return diff(_that);case BridgeAcpToolContent_Terminal():
return terminal(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpToolContent_Content value)?  content,TResult? Function( BridgeAcpToolContent_Diff value)?  diff,TResult? Function( BridgeAcpToolContent_Terminal value)?  terminal,}){
final _that = this;
switch (_that) {
case BridgeAcpToolContent_Content() when content != null:
return content(_that);case BridgeAcpToolContent_Diff() when diff != null:
return diff(_that);case BridgeAcpToolContent_Terminal() when terminal != null:
return terminal(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAcpContentBlock content,  Map<String, BridgeAcpJsonValue>? meta)?  content,TResult Function( String path,  String? oldText,  String newText,  Map<String, BridgeAcpJsonValue>? meta)?  diff,TResult Function( String terminalId,  Map<String, BridgeAcpJsonValue>? meta)?  terminal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpToolContent_Content() when content != null:
return content(_that.content,_that.meta);case BridgeAcpToolContent_Diff() when diff != null:
return diff(_that.path,_that.oldText,_that.newText,_that.meta);case BridgeAcpToolContent_Terminal() when terminal != null:
return terminal(_that.terminalId,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAcpContentBlock content,  Map<String, BridgeAcpJsonValue>? meta)  content,required TResult Function( String path,  String? oldText,  String newText,  Map<String, BridgeAcpJsonValue>? meta)  diff,required TResult Function( String terminalId,  Map<String, BridgeAcpJsonValue>? meta)  terminal,}) {final _that = this;
switch (_that) {
case BridgeAcpToolContent_Content():
return content(_that.content,_that.meta);case BridgeAcpToolContent_Diff():
return diff(_that.path,_that.oldText,_that.newText,_that.meta);case BridgeAcpToolContent_Terminal():
return terminal(_that.terminalId,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAcpContentBlock content,  Map<String, BridgeAcpJsonValue>? meta)?  content,TResult? Function( String path,  String? oldText,  String newText,  Map<String, BridgeAcpJsonValue>? meta)?  diff,TResult? Function( String terminalId,  Map<String, BridgeAcpJsonValue>? meta)?  terminal,}) {final _that = this;
switch (_that) {
case BridgeAcpToolContent_Content() when content != null:
return content(_that.content,_that.meta);case BridgeAcpToolContent_Diff() when diff != null:
return diff(_that.path,_that.oldText,_that.newText,_that.meta);case BridgeAcpToolContent_Terminal() when terminal != null:
return terminal(_that.terminalId,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpToolContent_Content extends BridgeAcpToolContent {
  const BridgeAcpToolContent_Content({required this.content,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  BridgeAcpContentBlock content;
 final  Map<String, BridgeAcpJsonValue>? _meta;
@override Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpToolContent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpToolContent_ContentCopyWith<BridgeAcpToolContent_Content> get copyWith => _$BridgeAcpToolContent_ContentCopyWithImpl<BridgeAcpToolContent_Content>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpToolContent_Content&&(identical(other.content, content) || other.content == content)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,content,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpToolContent.content(content: $content, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpToolContent_ContentCopyWith<$Res> implements $BridgeAcpToolContentCopyWith<$Res> {
  factory $BridgeAcpToolContent_ContentCopyWith(BridgeAcpToolContent_Content value, $Res Function(BridgeAcpToolContent_Content) _then) = _$BridgeAcpToolContent_ContentCopyWithImpl;
@override @useResult
$Res call({
 BridgeAcpContentBlock content, Map<String, BridgeAcpJsonValue>? meta
});


$BridgeAcpContentBlockCopyWith<$Res> get content;

}
/// @nodoc
class _$BridgeAcpToolContent_ContentCopyWithImpl<$Res>
    implements $BridgeAcpToolContent_ContentCopyWith<$Res> {
  _$BridgeAcpToolContent_ContentCopyWithImpl(this._self, this._then);

  final BridgeAcpToolContent_Content _self;
  final $Res Function(BridgeAcpToolContent_Content) _then;

/// Create a copy of BridgeAcpToolContent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? content = null,Object? meta = freezed,}) {
  return _then(BridgeAcpToolContent_Content(
content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as BridgeAcpContentBlock,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}

/// Create a copy of BridgeAcpToolContent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpContentBlockCopyWith<$Res> get content {

  return $BridgeAcpContentBlockCopyWith<$Res>(_self.content, (value) {
    return _then(_self.copyWith(content: value));
  });
}
}

/// @nodoc


class BridgeAcpToolContent_Diff extends BridgeAcpToolContent {
  const BridgeAcpToolContent_Diff({required this.path, this.oldText, required this.newText,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  String path;
 final  String? oldText;
 final  String newText;
 final  Map<String, BridgeAcpJsonValue>? _meta;
@override Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpToolContent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpToolContent_DiffCopyWith<BridgeAcpToolContent_Diff> get copyWith => _$BridgeAcpToolContent_DiffCopyWithImpl<BridgeAcpToolContent_Diff>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpToolContent_Diff&&(identical(other.path, path) || other.path == path)&&(identical(other.oldText, oldText) || other.oldText == oldText)&&(identical(other.newText, newText) || other.newText == newText)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path,oldText,newText,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpToolContent.diff(path: $path, oldText: $oldText, newText: $newText, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpToolContent_DiffCopyWith<$Res> implements $BridgeAcpToolContentCopyWith<$Res> {
  factory $BridgeAcpToolContent_DiffCopyWith(BridgeAcpToolContent_Diff value, $Res Function(BridgeAcpToolContent_Diff) _then) = _$BridgeAcpToolContent_DiffCopyWithImpl;
@override @useResult
$Res call({
 String path, String? oldText, String newText, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpToolContent_DiffCopyWithImpl<$Res>
    implements $BridgeAcpToolContent_DiffCopyWith<$Res> {
  _$BridgeAcpToolContent_DiffCopyWithImpl(this._self, this._then);

  final BridgeAcpToolContent_Diff _self;
  final $Res Function(BridgeAcpToolContent_Diff) _then;

/// Create a copy of BridgeAcpToolContent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? oldText = freezed,Object? newText = null,Object? meta = freezed,}) {
  return _then(BridgeAcpToolContent_Diff(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,oldText: freezed == oldText ? _self.oldText : oldText // ignore: cast_nullable_to_non_nullable
as String?,newText: null == newText ? _self.newText : newText // ignore: cast_nullable_to_non_nullable
as String,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpToolContent_Terminal extends BridgeAcpToolContent {
  const BridgeAcpToolContent_Terminal({required this.terminalId,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  String terminalId;
 final  Map<String, BridgeAcpJsonValue>? _meta;
@override Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpToolContent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpToolContent_TerminalCopyWith<BridgeAcpToolContent_Terminal> get copyWith => _$BridgeAcpToolContent_TerminalCopyWithImpl<BridgeAcpToolContent_Terminal>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpToolContent_Terminal&&(identical(other.terminalId, terminalId) || other.terminalId == terminalId)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,terminalId,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpToolContent.terminal(terminalId: $terminalId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpToolContent_TerminalCopyWith<$Res> implements $BridgeAcpToolContentCopyWith<$Res> {
  factory $BridgeAcpToolContent_TerminalCopyWith(BridgeAcpToolContent_Terminal value, $Res Function(BridgeAcpToolContent_Terminal) _then) = _$BridgeAcpToolContent_TerminalCopyWithImpl;
@override @useResult
$Res call({
 String terminalId, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpToolContent_TerminalCopyWithImpl<$Res>
    implements $BridgeAcpToolContent_TerminalCopyWith<$Res> {
  _$BridgeAcpToolContent_TerminalCopyWithImpl(this._self, this._then);

  final BridgeAcpToolContent_Terminal _self;
  final $Res Function(BridgeAcpToolContent_Terminal) _then;

/// Create a copy of BridgeAcpToolContent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? terminalId = null,Object? meta = freezed,}) {
  return _then(BridgeAcpToolContent_Terminal(
terminalId: null == terminalId ? _self.terminalId : terminalId // ignore: cast_nullable_to_non_nullable
as String,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

// dart format on
