// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_business.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAcpBusinessError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpBusinessError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpBusinessError()';
}


}

/// @nodoc
class $BridgeAcpBusinessErrorCopyWith<$Res>  {
$BridgeAcpBusinessErrorCopyWith(BridgeAcpBusinessError _, $Res Function(BridgeAcpBusinessError) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpBusinessError].
extension BridgeAcpBusinessErrorPatterns on BridgeAcpBusinessError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpBusinessError_Runtime value)?  runtime,TResult Function( BridgeAcpBusinessError_Business value)?  business,TResult Function( BridgeAcpBusinessError_Unsupported value)?  unsupported,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpBusinessError_Runtime() when runtime != null:
return runtime(_that);case BridgeAcpBusinessError_Business() when business != null:
return business(_that);case BridgeAcpBusinessError_Unsupported() when unsupported != null:
return unsupported(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpBusinessError_Runtime value)  runtime,required TResult Function( BridgeAcpBusinessError_Business value)  business,required TResult Function( BridgeAcpBusinessError_Unsupported value)  unsupported,}){
final _that = this;
switch (_that) {
case BridgeAcpBusinessError_Runtime():
return runtime(_that);case BridgeAcpBusinessError_Business():
return business(_that);case BridgeAcpBusinessError_Unsupported():
return unsupported(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpBusinessError_Runtime value)?  runtime,TResult? Function( BridgeAcpBusinessError_Business value)?  business,TResult? Function( BridgeAcpBusinessError_Unsupported value)?  unsupported,}){
final _that = this;
switch (_that) {
case BridgeAcpBusinessError_Runtime() when runtime != null:
return runtime(_that);case BridgeAcpBusinessError_Business() when business != null:
return business(_that);case BridgeAcpBusinessError_Unsupported() when unsupported != null:
return unsupported(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeError field0)?  runtime,TResult Function( BridgeAcpBusinessFailure field0)?  business,TResult Function( String typeName)?  unsupported,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpBusinessError_Runtime() when runtime != null:
return runtime(_that.field0);case BridgeAcpBusinessError_Business() when business != null:
return business(_that.field0);case BridgeAcpBusinessError_Unsupported() when unsupported != null:
return unsupported(_that.typeName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeError field0)  runtime,required TResult Function( BridgeAcpBusinessFailure field0)  business,required TResult Function( String typeName)  unsupported,}) {final _that = this;
switch (_that) {
case BridgeAcpBusinessError_Runtime():
return runtime(_that.field0);case BridgeAcpBusinessError_Business():
return business(_that.field0);case BridgeAcpBusinessError_Unsupported():
return unsupported(_that.typeName);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeError field0)?  runtime,TResult? Function( BridgeAcpBusinessFailure field0)?  business,TResult? Function( String typeName)?  unsupported,}) {final _that = this;
switch (_that) {
case BridgeAcpBusinessError_Runtime() when runtime != null:
return runtime(_that.field0);case BridgeAcpBusinessError_Business() when business != null:
return business(_that.field0);case BridgeAcpBusinessError_Unsupported() when unsupported != null:
return unsupported(_that.typeName);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpBusinessError_Runtime extends BridgeAcpBusinessError {
  const BridgeAcpBusinessError_Runtime(this.field0): super._();


 final  BridgeError field0;

/// Create a copy of BridgeAcpBusinessError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpBusinessError_RuntimeCopyWith<BridgeAcpBusinessError_Runtime> get copyWith => _$BridgeAcpBusinessError_RuntimeCopyWithImpl<BridgeAcpBusinessError_Runtime>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpBusinessError_Runtime&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeAcpBusinessError.runtime(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpBusinessError_RuntimeCopyWith<$Res> implements $BridgeAcpBusinessErrorCopyWith<$Res> {
  factory $BridgeAcpBusinessError_RuntimeCopyWith(BridgeAcpBusinessError_Runtime value, $Res Function(BridgeAcpBusinessError_Runtime) _then) = _$BridgeAcpBusinessError_RuntimeCopyWithImpl;
@useResult
$Res call({
 BridgeError field0
});




}
/// @nodoc
class _$BridgeAcpBusinessError_RuntimeCopyWithImpl<$Res>
    implements $BridgeAcpBusinessError_RuntimeCopyWith<$Res> {
  _$BridgeAcpBusinessError_RuntimeCopyWithImpl(this._self, this._then);

  final BridgeAcpBusinessError_Runtime _self;
  final $Res Function(BridgeAcpBusinessError_Runtime) _then;

/// Create a copy of BridgeAcpBusinessError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeAcpBusinessError_Runtime(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeAcpBusinessError_Business extends BridgeAcpBusinessError {
  const BridgeAcpBusinessError_Business(this.field0): super._();


 final  BridgeAcpBusinessFailure field0;

/// Create a copy of BridgeAcpBusinessError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpBusinessError_BusinessCopyWith<BridgeAcpBusinessError_Business> get copyWith => _$BridgeAcpBusinessError_BusinessCopyWithImpl<BridgeAcpBusinessError_Business>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpBusinessError_Business&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeAcpBusinessError.business(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpBusinessError_BusinessCopyWith<$Res> implements $BridgeAcpBusinessErrorCopyWith<$Res> {
  factory $BridgeAcpBusinessError_BusinessCopyWith(BridgeAcpBusinessError_Business value, $Res Function(BridgeAcpBusinessError_Business) _then) = _$BridgeAcpBusinessError_BusinessCopyWithImpl;
@useResult
$Res call({
 BridgeAcpBusinessFailure field0
});




}
/// @nodoc
class _$BridgeAcpBusinessError_BusinessCopyWithImpl<$Res>
    implements $BridgeAcpBusinessError_BusinessCopyWith<$Res> {
  _$BridgeAcpBusinessError_BusinessCopyWithImpl(this._self, this._then);

  final BridgeAcpBusinessError_Business _self;
  final $Res Function(BridgeAcpBusinessError_Business) _then;

/// Create a copy of BridgeAcpBusinessError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeAcpBusinessError_Business(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeAcpBusinessFailure,
  ));
}


}

/// @nodoc


class BridgeAcpBusinessError_Unsupported extends BridgeAcpBusinessError {
  const BridgeAcpBusinessError_Unsupported({required this.typeName}): super._();


 final  String typeName;

/// Create a copy of BridgeAcpBusinessError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpBusinessError_UnsupportedCopyWith<BridgeAcpBusinessError_Unsupported> get copyWith => _$BridgeAcpBusinessError_UnsupportedCopyWithImpl<BridgeAcpBusinessError_Unsupported>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpBusinessError_Unsupported&&(identical(other.typeName, typeName) || other.typeName == typeName));
}


@override
int get hashCode {
    return Object.hash(runtimeType,typeName);
}

@override
String toString() {
    return 'BridgeAcpBusinessError.unsupported(typeName: $typeName)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpBusinessError_UnsupportedCopyWith<$Res> implements $BridgeAcpBusinessErrorCopyWith<$Res> {
  factory $BridgeAcpBusinessError_UnsupportedCopyWith(BridgeAcpBusinessError_Unsupported value, $Res Function(BridgeAcpBusinessError_Unsupported) _then) = _$BridgeAcpBusinessError_UnsupportedCopyWithImpl;
@useResult
$Res call({
 String typeName
});




}
/// @nodoc
class _$BridgeAcpBusinessError_UnsupportedCopyWithImpl<$Res>
    implements $BridgeAcpBusinessError_UnsupportedCopyWith<$Res> {
  _$BridgeAcpBusinessError_UnsupportedCopyWithImpl(this._self, this._then);

  final BridgeAcpBusinessError_Unsupported _self;
  final $Res Function(BridgeAcpBusinessError_Unsupported) _then;

/// Create a copy of BridgeAcpBusinessError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? typeName = null,}) {
  return _then(BridgeAcpBusinessError_Unsupported(
typeName: null == typeName ? _self.typeName : typeName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpConfigCategory {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigCategory);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpConfigCategory()';
}


}

/// @nodoc
class $BridgeAcpConfigCategoryCopyWith<$Res>  {
$BridgeAcpConfigCategoryCopyWith(BridgeAcpConfigCategory _, $Res Function(BridgeAcpConfigCategory) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpConfigCategory].
extension BridgeAcpConfigCategoryPatterns on BridgeAcpConfigCategory {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpConfigCategory_Mode value)?  mode,TResult Function( BridgeAcpConfigCategory_Model value)?  model,TResult Function( BridgeAcpConfigCategory_ModelConfig value)?  modelConfig,TResult Function( BridgeAcpConfigCategory_ThoughtLevel value)?  thoughtLevel,TResult Function( BridgeAcpConfigCategory_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpConfigCategory_Mode() when mode != null:
return mode(_that);case BridgeAcpConfigCategory_Model() when model != null:
return model(_that);case BridgeAcpConfigCategory_ModelConfig() when modelConfig != null:
return modelConfig(_that);case BridgeAcpConfigCategory_ThoughtLevel() when thoughtLevel != null:
return thoughtLevel(_that);case BridgeAcpConfigCategory_Other() when other != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpConfigCategory_Mode value)  mode,required TResult Function( BridgeAcpConfigCategory_Model value)  model,required TResult Function( BridgeAcpConfigCategory_ModelConfig value)  modelConfig,required TResult Function( BridgeAcpConfigCategory_ThoughtLevel value)  thoughtLevel,required TResult Function( BridgeAcpConfigCategory_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeAcpConfigCategory_Mode():
return mode(_that);case BridgeAcpConfigCategory_Model():
return model(_that);case BridgeAcpConfigCategory_ModelConfig():
return modelConfig(_that);case BridgeAcpConfigCategory_ThoughtLevel():
return thoughtLevel(_that);case BridgeAcpConfigCategory_Other():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpConfigCategory_Mode value)?  mode,TResult? Function( BridgeAcpConfigCategory_Model value)?  model,TResult? Function( BridgeAcpConfigCategory_ModelConfig value)?  modelConfig,TResult? Function( BridgeAcpConfigCategory_ThoughtLevel value)?  thoughtLevel,TResult? Function( BridgeAcpConfigCategory_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeAcpConfigCategory_Mode() when mode != null:
return mode(_that);case BridgeAcpConfigCategory_Model() when model != null:
return model(_that);case BridgeAcpConfigCategory_ModelConfig() when modelConfig != null:
return modelConfig(_that);case BridgeAcpConfigCategory_ThoughtLevel() when thoughtLevel != null:
return thoughtLevel(_that);case BridgeAcpConfigCategory_Other() when other != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  mode,TResult Function()?  model,TResult Function()?  modelConfig,TResult Function()?  thoughtLevel,TResult Function( String value)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpConfigCategory_Mode() when mode != null:
return mode();case BridgeAcpConfigCategory_Model() when model != null:
return model();case BridgeAcpConfigCategory_ModelConfig() when modelConfig != null:
return modelConfig();case BridgeAcpConfigCategory_ThoughtLevel() when thoughtLevel != null:
return thoughtLevel();case BridgeAcpConfigCategory_Other() when other != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  mode,required TResult Function()  model,required TResult Function()  modelConfig,required TResult Function()  thoughtLevel,required TResult Function( String value)  other,}) {final _that = this;
switch (_that) {
case BridgeAcpConfigCategory_Mode():
return mode();case BridgeAcpConfigCategory_Model():
return model();case BridgeAcpConfigCategory_ModelConfig():
return modelConfig();case BridgeAcpConfigCategory_ThoughtLevel():
return thoughtLevel();case BridgeAcpConfigCategory_Other():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  mode,TResult? Function()?  model,TResult? Function()?  modelConfig,TResult? Function()?  thoughtLevel,TResult? Function( String value)?  other,}) {final _that = this;
switch (_that) {
case BridgeAcpConfigCategory_Mode() when mode != null:
return mode();case BridgeAcpConfigCategory_Model() when model != null:
return model();case BridgeAcpConfigCategory_ModelConfig() when modelConfig != null:
return modelConfig();case BridgeAcpConfigCategory_ThoughtLevel() when thoughtLevel != null:
return thoughtLevel();case BridgeAcpConfigCategory_Other() when other != null:
return other(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpConfigCategory_Mode extends BridgeAcpConfigCategory {
  const BridgeAcpConfigCategory_Mode(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigCategory_Mode);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpConfigCategory.mode()';
}


}




/// @nodoc


class BridgeAcpConfigCategory_Model extends BridgeAcpConfigCategory {
  const BridgeAcpConfigCategory_Model(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigCategory_Model);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpConfigCategory.model()';
}


}




/// @nodoc


class BridgeAcpConfigCategory_ModelConfig extends BridgeAcpConfigCategory {
  const BridgeAcpConfigCategory_ModelConfig(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigCategory_ModelConfig);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpConfigCategory.modelConfig()';
}


}




/// @nodoc


class BridgeAcpConfigCategory_ThoughtLevel extends BridgeAcpConfigCategory {
  const BridgeAcpConfigCategory_ThoughtLevel(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigCategory_ThoughtLevel);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpConfigCategory.thoughtLevel()';
}


}




/// @nodoc


class BridgeAcpConfigCategory_Other extends BridgeAcpConfigCategory {
  const BridgeAcpConfigCategory_Other({required this.value}): super._();


 final  String value;

/// Create a copy of BridgeAcpConfigCategory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpConfigCategory_OtherCopyWith<BridgeAcpConfigCategory_Other> get copyWith => _$BridgeAcpConfigCategory_OtherCopyWithImpl<BridgeAcpConfigCategory_Other>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigCategory_Other&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpConfigCategory.other(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpConfigCategory_OtherCopyWith<$Res> implements $BridgeAcpConfigCategoryCopyWith<$Res> {
  factory $BridgeAcpConfigCategory_OtherCopyWith(BridgeAcpConfigCategory_Other value, $Res Function(BridgeAcpConfigCategory_Other) _then) = _$BridgeAcpConfigCategory_OtherCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$BridgeAcpConfigCategory_OtherCopyWithImpl<$Res>
    implements $BridgeAcpConfigCategory_OtherCopyWith<$Res> {
  _$BridgeAcpConfigCategory_OtherCopyWithImpl(this._self, this._then);

  final BridgeAcpConfigCategory_Other _self;
  final $Res Function(BridgeAcpConfigCategory_Other) _then;

/// Create a copy of BridgeAcpConfigCategory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpConfigCategory_Other(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpConfigKind {

 Object get currentValue;



@override
bool operator ==(Object other) {
  final _this = this as BridgeAcpConfigKind;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigKind&&const DeepCollectionEquality().equals(other.currentValue, _this.currentValue));
}


@override
int get hashCode {
  final _this = this as BridgeAcpConfigKind;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.currentValue));
}

@override
String toString() {
  final _this = this as BridgeAcpConfigKind;
  return 'BridgeAcpConfigKind(currentValue: ${_this.currentValue})';
}


}

/// @nodoc
class $BridgeAcpConfigKindCopyWith<$Res>  {
$BridgeAcpConfigKindCopyWith(BridgeAcpConfigKind _, $Res Function(BridgeAcpConfigKind) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpConfigKind].
extension BridgeAcpConfigKindPatterns on BridgeAcpConfigKind {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpConfigKind_Select value)?  select,TResult Function( BridgeAcpConfigKind_Boolean value)?  boolean,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpConfigKind_Select() when select != null:
return select(_that);case BridgeAcpConfigKind_Boolean() when boolean != null:
return boolean(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpConfigKind_Select value)  select,required TResult Function( BridgeAcpConfigKind_Boolean value)  boolean,}){
final _that = this;
switch (_that) {
case BridgeAcpConfigKind_Select():
return select(_that);case BridgeAcpConfigKind_Boolean():
return boolean(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpConfigKind_Select value)?  select,TResult? Function( BridgeAcpConfigKind_Boolean value)?  boolean,}){
final _that = this;
switch (_that) {
case BridgeAcpConfigKind_Select() when select != null:
return select(_that);case BridgeAcpConfigKind_Boolean() when boolean != null:
return boolean(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAcpConfigValueId currentValue,  BridgeAcpSelectOptions options)?  select,TResult Function( bool currentValue)?  boolean,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpConfigKind_Select() when select != null:
return select(_that.currentValue,_that.options);case BridgeAcpConfigKind_Boolean() when boolean != null:
return boolean(_that.currentValue);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAcpConfigValueId currentValue,  BridgeAcpSelectOptions options)  select,required TResult Function( bool currentValue)  boolean,}) {final _that = this;
switch (_that) {
case BridgeAcpConfigKind_Select():
return select(_that.currentValue,_that.options);case BridgeAcpConfigKind_Boolean():
return boolean(_that.currentValue);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAcpConfigValueId currentValue,  BridgeAcpSelectOptions options)?  select,TResult? Function( bool currentValue)?  boolean,}) {final _that = this;
switch (_that) {
case BridgeAcpConfigKind_Select() when select != null:
return select(_that.currentValue,_that.options);case BridgeAcpConfigKind_Boolean() when boolean != null:
return boolean(_that.currentValue);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpConfigKind_Select extends BridgeAcpConfigKind {
  const BridgeAcpConfigKind_Select({required this.currentValue, required this.options}): super._();


@override final  BridgeAcpConfigValueId currentValue;
 final  BridgeAcpSelectOptions options;

/// Create a copy of BridgeAcpConfigKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpConfigKind_SelectCopyWith<BridgeAcpConfigKind_Select> get copyWith => _$BridgeAcpConfigKind_SelectCopyWithImpl<BridgeAcpConfigKind_Select>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigKind_Select&&(identical(other.currentValue, currentValue) || other.currentValue == currentValue)&&(identical(other.options, options) || other.options == options));
}


@override
int get hashCode {
    return Object.hash(runtimeType,currentValue,options);
}

@override
String toString() {
    return 'BridgeAcpConfigKind.select(currentValue: $currentValue, options: $options)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpConfigKind_SelectCopyWith<$Res> implements $BridgeAcpConfigKindCopyWith<$Res> {
  factory $BridgeAcpConfigKind_SelectCopyWith(BridgeAcpConfigKind_Select value, $Res Function(BridgeAcpConfigKind_Select) _then) = _$BridgeAcpConfigKind_SelectCopyWithImpl;
@useResult
$Res call({
 BridgeAcpConfigValueId currentValue, BridgeAcpSelectOptions options
});


$BridgeAcpSelectOptionsCopyWith<$Res> get options;

}
/// @nodoc
class _$BridgeAcpConfigKind_SelectCopyWithImpl<$Res>
    implements $BridgeAcpConfigKind_SelectCopyWith<$Res> {
  _$BridgeAcpConfigKind_SelectCopyWithImpl(this._self, this._then);

  final BridgeAcpConfigKind_Select _self;
  final $Res Function(BridgeAcpConfigKind_Select) _then;

/// Create a copy of BridgeAcpConfigKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? currentValue = null,Object? options = null,}) {
  return _then(BridgeAcpConfigKind_Select(
currentValue: null == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as BridgeAcpConfigValueId,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as BridgeAcpSelectOptions,
  ));
}

/// Create a copy of BridgeAcpConfigKind
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpSelectOptionsCopyWith<$Res> get options {

  return $BridgeAcpSelectOptionsCopyWith<$Res>(_self.options, (value) {
    return _then(_self.copyWith(options: value));
  });
}
}

/// @nodoc


class BridgeAcpConfigKind_Boolean extends BridgeAcpConfigKind {
  const BridgeAcpConfigKind_Boolean({required this.currentValue}): super._();


@override final  bool currentValue;

/// Create a copy of BridgeAcpConfigKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpConfigKind_BooleanCopyWith<BridgeAcpConfigKind_Boolean> get copyWith => _$BridgeAcpConfigKind_BooleanCopyWithImpl<BridgeAcpConfigKind_Boolean>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigKind_Boolean&&(identical(other.currentValue, currentValue) || other.currentValue == currentValue));
}


@override
int get hashCode {
    return Object.hash(runtimeType,currentValue);
}

@override
String toString() {
    return 'BridgeAcpConfigKind.boolean(currentValue: $currentValue)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpConfigKind_BooleanCopyWith<$Res> implements $BridgeAcpConfigKindCopyWith<$Res> {
  factory $BridgeAcpConfigKind_BooleanCopyWith(BridgeAcpConfigKind_Boolean value, $Res Function(BridgeAcpConfigKind_Boolean) _then) = _$BridgeAcpConfigKind_BooleanCopyWithImpl;
@useResult
$Res call({
 bool currentValue
});




}
/// @nodoc
class _$BridgeAcpConfigKind_BooleanCopyWithImpl<$Res>
    implements $BridgeAcpConfigKind_BooleanCopyWith<$Res> {
  _$BridgeAcpConfigKind_BooleanCopyWithImpl(this._self, this._then);

  final BridgeAcpConfigKind_Boolean _self;
  final $Res Function(BridgeAcpConfigKind_Boolean) _then;

/// Create a copy of BridgeAcpConfigKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? currentValue = null,}) {
  return _then(BridgeAcpConfigKind_Boolean(
currentValue: null == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpConfigValue {

 Object get value;



@override
bool operator ==(Object other) {
  final _this = this as BridgeAcpConfigValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigValue&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeAcpConfigValue;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeAcpConfigValue;
  return 'BridgeAcpConfigValue(value: ${_this.value})';
}


}

/// @nodoc
class $BridgeAcpConfigValueCopyWith<$Res>  {
$BridgeAcpConfigValueCopyWith(BridgeAcpConfigValue _, $Res Function(BridgeAcpConfigValue) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpConfigValue].
extension BridgeAcpConfigValuePatterns on BridgeAcpConfigValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpConfigValue_Boolean value)?  boolean,TResult Function( BridgeAcpConfigValue_ValueId value)?  valueId,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpConfigValue_Boolean() when boolean != null:
return boolean(_that);case BridgeAcpConfigValue_ValueId() when valueId != null:
return valueId(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpConfigValue_Boolean value)  boolean,required TResult Function( BridgeAcpConfigValue_ValueId value)  valueId,}){
final _that = this;
switch (_that) {
case BridgeAcpConfigValue_Boolean():
return boolean(_that);case BridgeAcpConfigValue_ValueId():
return valueId(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpConfigValue_Boolean value)?  boolean,TResult? Function( BridgeAcpConfigValue_ValueId value)?  valueId,}){
final _that = this;
switch (_that) {
case BridgeAcpConfigValue_Boolean() when boolean != null:
return boolean(_that);case BridgeAcpConfigValue_ValueId() when valueId != null:
return valueId(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool value)?  boolean,TResult Function( BridgeAcpConfigValueId value)?  valueId,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpConfigValue_Boolean() when boolean != null:
return boolean(_that.value);case BridgeAcpConfigValue_ValueId() when valueId != null:
return valueId(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool value)  boolean,required TResult Function( BridgeAcpConfigValueId value)  valueId,}) {final _that = this;
switch (_that) {
case BridgeAcpConfigValue_Boolean():
return boolean(_that.value);case BridgeAcpConfigValue_ValueId():
return valueId(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool value)?  boolean,TResult? Function( BridgeAcpConfigValueId value)?  valueId,}) {final _that = this;
switch (_that) {
case BridgeAcpConfigValue_Boolean() when boolean != null:
return boolean(_that.value);case BridgeAcpConfigValue_ValueId() when valueId != null:
return valueId(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpConfigValue_Boolean extends BridgeAcpConfigValue {
  const BridgeAcpConfigValue_Boolean({required this.value}): super._();


@override final  bool value;

/// Create a copy of BridgeAcpConfigValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpConfigValue_BooleanCopyWith<BridgeAcpConfigValue_Boolean> get copyWith => _$BridgeAcpConfigValue_BooleanCopyWithImpl<BridgeAcpConfigValue_Boolean>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigValue_Boolean&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpConfigValue.boolean(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpConfigValue_BooleanCopyWith<$Res> implements $BridgeAcpConfigValueCopyWith<$Res> {
  factory $BridgeAcpConfigValue_BooleanCopyWith(BridgeAcpConfigValue_Boolean value, $Res Function(BridgeAcpConfigValue_Boolean) _then) = _$BridgeAcpConfigValue_BooleanCopyWithImpl;
@useResult
$Res call({
 bool value
});




}
/// @nodoc
class _$BridgeAcpConfigValue_BooleanCopyWithImpl<$Res>
    implements $BridgeAcpConfigValue_BooleanCopyWith<$Res> {
  _$BridgeAcpConfigValue_BooleanCopyWithImpl(this._self, this._then);

  final BridgeAcpConfigValue_Boolean _self;
  final $Res Function(BridgeAcpConfigValue_Boolean) _then;

/// Create a copy of BridgeAcpConfigValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpConfigValue_Boolean(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgeAcpConfigValue_ValueId extends BridgeAcpConfigValue {
  const BridgeAcpConfigValue_ValueId({required this.value}): super._();


@override final  BridgeAcpConfigValueId value;

/// Create a copy of BridgeAcpConfigValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpConfigValue_ValueIdCopyWith<BridgeAcpConfigValue_ValueId> get copyWith => _$BridgeAcpConfigValue_ValueIdCopyWithImpl<BridgeAcpConfigValue_ValueId>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpConfigValue_ValueId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpConfigValue.valueId(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpConfigValue_ValueIdCopyWith<$Res> implements $BridgeAcpConfigValueCopyWith<$Res> {
  factory $BridgeAcpConfigValue_ValueIdCopyWith(BridgeAcpConfigValue_ValueId value, $Res Function(BridgeAcpConfigValue_ValueId) _then) = _$BridgeAcpConfigValue_ValueIdCopyWithImpl;
@useResult
$Res call({
 BridgeAcpConfigValueId value
});




}
/// @nodoc
class _$BridgeAcpConfigValue_ValueIdCopyWithImpl<$Res>
    implements $BridgeAcpConfigValue_ValueIdCopyWith<$Res> {
  _$BridgeAcpConfigValue_ValueIdCopyWithImpl(this._self, this._then);

  final BridgeAcpConfigValue_ValueId _self;
  final $Res Function(BridgeAcpConfigValue_ValueId) _then;

/// Create a copy of BridgeAcpConfigValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpConfigValue_ValueId(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAcpConfigValueId,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpJsonNumber {

 Object get value;



@override
bool operator ==(Object other) {
  final _this = this as BridgeAcpJsonNumber;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpJsonNumber&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as BridgeAcpJsonNumber;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as BridgeAcpJsonNumber;
  return 'BridgeAcpJsonNumber(value: ${_this.value})';
}


}

/// @nodoc
class $BridgeAcpJsonNumberCopyWith<$Res>  {
$BridgeAcpJsonNumberCopyWith(BridgeAcpJsonNumber _, $Res Function(BridgeAcpJsonNumber) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpJsonNumber].
extension BridgeAcpJsonNumberPatterns on BridgeAcpJsonNumber {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpJsonNumber_Signed value)?  signed,TResult Function( BridgeAcpJsonNumber_Unsigned value)?  unsigned,TResult Function( BridgeAcpJsonNumber_Float value)?  float,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpJsonNumber_Signed() when signed != null:
return signed(_that);case BridgeAcpJsonNumber_Unsigned() when unsigned != null:
return unsigned(_that);case BridgeAcpJsonNumber_Float() when float != null:
return float(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpJsonNumber_Signed value)  signed,required TResult Function( BridgeAcpJsonNumber_Unsigned value)  unsigned,required TResult Function( BridgeAcpJsonNumber_Float value)  float,}){
final _that = this;
switch (_that) {
case BridgeAcpJsonNumber_Signed():
return signed(_that);case BridgeAcpJsonNumber_Unsigned():
return unsigned(_that);case BridgeAcpJsonNumber_Float():
return float(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpJsonNumber_Signed value)?  signed,TResult? Function( BridgeAcpJsonNumber_Unsigned value)?  unsigned,TResult? Function( BridgeAcpJsonNumber_Float value)?  float,}){
final _that = this;
switch (_that) {
case BridgeAcpJsonNumber_Signed() when signed != null:
return signed(_that);case BridgeAcpJsonNumber_Unsigned() when unsigned != null:
return unsigned(_that);case BridgeAcpJsonNumber_Float() when float != null:
return float(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PlatformInt64 value)?  signed,TResult Function( BigInt value)?  unsigned,TResult Function( double value)?  float,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpJsonNumber_Signed() when signed != null:
return signed(_that.value);case BridgeAcpJsonNumber_Unsigned() when unsigned != null:
return unsigned(_that.value);case BridgeAcpJsonNumber_Float() when float != null:
return float(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PlatformInt64 value)  signed,required TResult Function( BigInt value)  unsigned,required TResult Function( double value)  float,}) {final _that = this;
switch (_that) {
case BridgeAcpJsonNumber_Signed():
return signed(_that.value);case BridgeAcpJsonNumber_Unsigned():
return unsigned(_that.value);case BridgeAcpJsonNumber_Float():
return float(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PlatformInt64 value)?  signed,TResult? Function( BigInt value)?  unsigned,TResult? Function( double value)?  float,}) {final _that = this;
switch (_that) {
case BridgeAcpJsonNumber_Signed() when signed != null:
return signed(_that.value);case BridgeAcpJsonNumber_Unsigned() when unsigned != null:
return unsigned(_that.value);case BridgeAcpJsonNumber_Float() when float != null:
return float(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpJsonNumber_Signed extends BridgeAcpJsonNumber {
  const BridgeAcpJsonNumber_Signed({required this.value}): super._();


@override final  PlatformInt64 value;

/// Create a copy of BridgeAcpJsonNumber
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpJsonNumber_SignedCopyWith<BridgeAcpJsonNumber_Signed> get copyWith => _$BridgeAcpJsonNumber_SignedCopyWithImpl<BridgeAcpJsonNumber_Signed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpJsonNumber_Signed&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpJsonNumber.signed(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpJsonNumber_SignedCopyWith<$Res> implements $BridgeAcpJsonNumberCopyWith<$Res> {
  factory $BridgeAcpJsonNumber_SignedCopyWith(BridgeAcpJsonNumber_Signed value, $Res Function(BridgeAcpJsonNumber_Signed) _then) = _$BridgeAcpJsonNumber_SignedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 value
});




}
/// @nodoc
class _$BridgeAcpJsonNumber_SignedCopyWithImpl<$Res>
    implements $BridgeAcpJsonNumber_SignedCopyWith<$Res> {
  _$BridgeAcpJsonNumber_SignedCopyWithImpl(this._self, this._then);

  final BridgeAcpJsonNumber_Signed _self;
  final $Res Function(BridgeAcpJsonNumber_Signed) _then;

/// Create a copy of BridgeAcpJsonNumber
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpJsonNumber_Signed(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeAcpJsonNumber_Unsigned extends BridgeAcpJsonNumber {
  const BridgeAcpJsonNumber_Unsigned({required this.value}): super._();


@override final  BigInt value;

/// Create a copy of BridgeAcpJsonNumber
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpJsonNumber_UnsignedCopyWith<BridgeAcpJsonNumber_Unsigned> get copyWith => _$BridgeAcpJsonNumber_UnsignedCopyWithImpl<BridgeAcpJsonNumber_Unsigned>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpJsonNumber_Unsigned&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpJsonNumber.unsigned(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpJsonNumber_UnsignedCopyWith<$Res> implements $BridgeAcpJsonNumberCopyWith<$Res> {
  factory $BridgeAcpJsonNumber_UnsignedCopyWith(BridgeAcpJsonNumber_Unsigned value, $Res Function(BridgeAcpJsonNumber_Unsigned) _then) = _$BridgeAcpJsonNumber_UnsignedCopyWithImpl;
@useResult
$Res call({
 BigInt value
});




}
/// @nodoc
class _$BridgeAcpJsonNumber_UnsignedCopyWithImpl<$Res>
    implements $BridgeAcpJsonNumber_UnsignedCopyWith<$Res> {
  _$BridgeAcpJsonNumber_UnsignedCopyWithImpl(this._self, this._then);

  final BridgeAcpJsonNumber_Unsigned _self;
  final $Res Function(BridgeAcpJsonNumber_Unsigned) _then;

/// Create a copy of BridgeAcpJsonNumber
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpJsonNumber_Unsigned(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeAcpJsonNumber_Float extends BridgeAcpJsonNumber {
  const BridgeAcpJsonNumber_Float({required this.value}): super._();


@override final  double value;

/// Create a copy of BridgeAcpJsonNumber
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpJsonNumber_FloatCopyWith<BridgeAcpJsonNumber_Float> get copyWith => _$BridgeAcpJsonNumber_FloatCopyWithImpl<BridgeAcpJsonNumber_Float>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpJsonNumber_Float&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpJsonNumber.float(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpJsonNumber_FloatCopyWith<$Res> implements $BridgeAcpJsonNumberCopyWith<$Res> {
  factory $BridgeAcpJsonNumber_FloatCopyWith(BridgeAcpJsonNumber_Float value, $Res Function(BridgeAcpJsonNumber_Float) _then) = _$BridgeAcpJsonNumber_FloatCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$BridgeAcpJsonNumber_FloatCopyWithImpl<$Res>
    implements $BridgeAcpJsonNumber_FloatCopyWith<$Res> {
  _$BridgeAcpJsonNumber_FloatCopyWithImpl(this._self, this._then);

  final BridgeAcpJsonNumber_Float _self;
  final $Res Function(BridgeAcpJsonNumber_Float) _then;

/// Create a copy of BridgeAcpJsonNumber
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpJsonNumber_Float(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpJsonValue {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpJsonValue);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpJsonValue()';
}


}

/// @nodoc
class $BridgeAcpJsonValueCopyWith<$Res>  {
$BridgeAcpJsonValueCopyWith(BridgeAcpJsonValue _, $Res Function(BridgeAcpJsonValue) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpJsonValue].
extension BridgeAcpJsonValuePatterns on BridgeAcpJsonValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpJsonValue_Null value)?  null_,TResult Function( BridgeAcpJsonValue_Bool value)?  bool,TResult Function( BridgeAcpJsonValue_Number value)?  number,TResult Function( BridgeAcpJsonValue_String value)?  string,TResult Function( BridgeAcpJsonValue_Array value)?  array,TResult Function( BridgeAcpJsonValue_Object value)?  object,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpJsonValue_Null() when null_ != null:
return null_(_that);case BridgeAcpJsonValue_Bool() when bool != null:
return bool(_that);case BridgeAcpJsonValue_Number() when number != null:
return number(_that);case BridgeAcpJsonValue_String() when string != null:
return string(_that);case BridgeAcpJsonValue_Array() when array != null:
return array(_that);case BridgeAcpJsonValue_Object() when object != null:
return object(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpJsonValue_Null value)  null_,required TResult Function( BridgeAcpJsonValue_Bool value)  bool,required TResult Function( BridgeAcpJsonValue_Number value)  number,required TResult Function( BridgeAcpJsonValue_String value)  string,required TResult Function( BridgeAcpJsonValue_Array value)  array,required TResult Function( BridgeAcpJsonValue_Object value)  object,}){
final _that = this;
switch (_that) {
case BridgeAcpJsonValue_Null():
return null_(_that);case BridgeAcpJsonValue_Bool():
return bool(_that);case BridgeAcpJsonValue_Number():
return number(_that);case BridgeAcpJsonValue_String():
return string(_that);case BridgeAcpJsonValue_Array():
return array(_that);case BridgeAcpJsonValue_Object():
return object(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpJsonValue_Null value)?  null_,TResult? Function( BridgeAcpJsonValue_Bool value)?  bool,TResult? Function( BridgeAcpJsonValue_Number value)?  number,TResult? Function( BridgeAcpJsonValue_String value)?  string,TResult? Function( BridgeAcpJsonValue_Array value)?  array,TResult? Function( BridgeAcpJsonValue_Object value)?  object,}){
final _that = this;
switch (_that) {
case BridgeAcpJsonValue_Null() when null_ != null:
return null_(_that);case BridgeAcpJsonValue_Bool() when bool != null:
return bool(_that);case BridgeAcpJsonValue_Number() when number != null:
return number(_that);case BridgeAcpJsonValue_String() when string != null:
return string(_that);case BridgeAcpJsonValue_Array() when array != null:
return array(_that);case BridgeAcpJsonValue_Object() when object != null:
return object(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  null_,TResult Function( bool value)?  bool,TResult Function( BridgeAcpJsonNumber value)?  number,TResult Function( String value)?  string,TResult Function( List<BridgeAcpJsonValue> values)?  array,TResult Function( Map<String, BridgeAcpJsonValue> fields)?  object,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpJsonValue_Null() when null_ != null:
return null_();case BridgeAcpJsonValue_Bool() when bool != null:
return bool(_that.value);case BridgeAcpJsonValue_Number() when number != null:
return number(_that.value);case BridgeAcpJsonValue_String() when string != null:
return string(_that.value);case BridgeAcpJsonValue_Array() when array != null:
return array(_that.values);case BridgeAcpJsonValue_Object() when object != null:
return object(_that.fields);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  null_,required TResult Function( bool value)  bool,required TResult Function( BridgeAcpJsonNumber value)  number,required TResult Function( String value)  string,required TResult Function( List<BridgeAcpJsonValue> values)  array,required TResult Function( Map<String, BridgeAcpJsonValue> fields)  object,}) {final _that = this;
switch (_that) {
case BridgeAcpJsonValue_Null():
return null_();case BridgeAcpJsonValue_Bool():
return bool(_that.value);case BridgeAcpJsonValue_Number():
return number(_that.value);case BridgeAcpJsonValue_String():
return string(_that.value);case BridgeAcpJsonValue_Array():
return array(_that.values);case BridgeAcpJsonValue_Object():
return object(_that.fields);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  null_,TResult? Function( bool value)?  bool,TResult? Function( BridgeAcpJsonNumber value)?  number,TResult? Function( String value)?  string,TResult? Function( List<BridgeAcpJsonValue> values)?  array,TResult? Function( Map<String, BridgeAcpJsonValue> fields)?  object,}) {final _that = this;
switch (_that) {
case BridgeAcpJsonValue_Null() when null_ != null:
return null_();case BridgeAcpJsonValue_Bool() when bool != null:
return bool(_that.value);case BridgeAcpJsonValue_Number() when number != null:
return number(_that.value);case BridgeAcpJsonValue_String() when string != null:
return string(_that.value);case BridgeAcpJsonValue_Array() when array != null:
return array(_that.values);case BridgeAcpJsonValue_Object() when object != null:
return object(_that.fields);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpJsonValue_Null extends BridgeAcpJsonValue {
  const BridgeAcpJsonValue_Null(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpJsonValue_Null);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpJsonValue.null_()';
}


}




/// @nodoc


class BridgeAcpJsonValue_Bool extends BridgeAcpJsonValue {
  const BridgeAcpJsonValue_Bool({required this.value}): super._();


 final  bool value;

/// Create a copy of BridgeAcpJsonValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpJsonValue_BoolCopyWith<BridgeAcpJsonValue_Bool> get copyWith => _$BridgeAcpJsonValue_BoolCopyWithImpl<BridgeAcpJsonValue_Bool>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpJsonValue_Bool&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpJsonValue.bool(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpJsonValue_BoolCopyWith<$Res> implements $BridgeAcpJsonValueCopyWith<$Res> {
  factory $BridgeAcpJsonValue_BoolCopyWith(BridgeAcpJsonValue_Bool value, $Res Function(BridgeAcpJsonValue_Bool) _then) = _$BridgeAcpJsonValue_BoolCopyWithImpl;
@useResult
$Res call({
 bool value
});




}
/// @nodoc
class _$BridgeAcpJsonValue_BoolCopyWithImpl<$Res>
    implements $BridgeAcpJsonValue_BoolCopyWith<$Res> {
  _$BridgeAcpJsonValue_BoolCopyWithImpl(this._self, this._then);

  final BridgeAcpJsonValue_Bool _self;
  final $Res Function(BridgeAcpJsonValue_Bool) _then;

/// Create a copy of BridgeAcpJsonValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpJsonValue_Bool(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgeAcpJsonValue_Number extends BridgeAcpJsonValue {
  const BridgeAcpJsonValue_Number({required this.value}): super._();


 final  BridgeAcpJsonNumber value;

/// Create a copy of BridgeAcpJsonValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpJsonValue_NumberCopyWith<BridgeAcpJsonValue_Number> get copyWith => _$BridgeAcpJsonValue_NumberCopyWithImpl<BridgeAcpJsonValue_Number>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpJsonValue_Number&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpJsonValue.number(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpJsonValue_NumberCopyWith<$Res> implements $BridgeAcpJsonValueCopyWith<$Res> {
  factory $BridgeAcpJsonValue_NumberCopyWith(BridgeAcpJsonValue_Number value, $Res Function(BridgeAcpJsonValue_Number) _then) = _$BridgeAcpJsonValue_NumberCopyWithImpl;
@useResult
$Res call({
 BridgeAcpJsonNumber value
});


$BridgeAcpJsonNumberCopyWith<$Res> get value;

}
/// @nodoc
class _$BridgeAcpJsonValue_NumberCopyWithImpl<$Res>
    implements $BridgeAcpJsonValue_NumberCopyWith<$Res> {
  _$BridgeAcpJsonValue_NumberCopyWithImpl(this._self, this._then);

  final BridgeAcpJsonValue_Number _self;
  final $Res Function(BridgeAcpJsonValue_Number) _then;

/// Create a copy of BridgeAcpJsonValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpJsonValue_Number(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgeAcpJsonNumber,
  ));
}

/// Create a copy of BridgeAcpJsonValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpJsonNumberCopyWith<$Res> get value {

  return $BridgeAcpJsonNumberCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class BridgeAcpJsonValue_String extends BridgeAcpJsonValue {
  const BridgeAcpJsonValue_String({required this.value}): super._();


 final  String value;

/// Create a copy of BridgeAcpJsonValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpJsonValue_StringCopyWith<BridgeAcpJsonValue_String> get copyWith => _$BridgeAcpJsonValue_StringCopyWithImpl<BridgeAcpJsonValue_String>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpJsonValue_String&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAcpJsonValue.string(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpJsonValue_StringCopyWith<$Res> implements $BridgeAcpJsonValueCopyWith<$Res> {
  factory $BridgeAcpJsonValue_StringCopyWith(BridgeAcpJsonValue_String value, $Res Function(BridgeAcpJsonValue_String) _then) = _$BridgeAcpJsonValue_StringCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$BridgeAcpJsonValue_StringCopyWithImpl<$Res>
    implements $BridgeAcpJsonValue_StringCopyWith<$Res> {
  _$BridgeAcpJsonValue_StringCopyWithImpl(this._self, this._then);

  final BridgeAcpJsonValue_String _self;
  final $Res Function(BridgeAcpJsonValue_String) _then;

/// Create a copy of BridgeAcpJsonValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAcpJsonValue_String(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpJsonValue_Array extends BridgeAcpJsonValue {
  const BridgeAcpJsonValue_Array({required  List<BridgeAcpJsonValue> values}): _values = values,super._();


 final  List<BridgeAcpJsonValue> _values;
 List<BridgeAcpJsonValue> get values {
  if (_values is EqualUnmodifiableListView) return _values;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_values);
}


/// Create a copy of BridgeAcpJsonValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpJsonValue_ArrayCopyWith<BridgeAcpJsonValue_Array> get copyWith => _$BridgeAcpJsonValue_ArrayCopyWithImpl<BridgeAcpJsonValue_Array>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpJsonValue_Array&&const DeepCollectionEquality().equals(other.values, _values));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_values));
}

@override
String toString() {
    return 'BridgeAcpJsonValue.array(values: $values)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpJsonValue_ArrayCopyWith<$Res> implements $BridgeAcpJsonValueCopyWith<$Res> {
  factory $BridgeAcpJsonValue_ArrayCopyWith(BridgeAcpJsonValue_Array value, $Res Function(BridgeAcpJsonValue_Array) _then) = _$BridgeAcpJsonValue_ArrayCopyWithImpl;
@useResult
$Res call({
 List<BridgeAcpJsonValue> values
});




}
/// @nodoc
class _$BridgeAcpJsonValue_ArrayCopyWithImpl<$Res>
    implements $BridgeAcpJsonValue_ArrayCopyWith<$Res> {
  _$BridgeAcpJsonValue_ArrayCopyWithImpl(this._self, this._then);

  final BridgeAcpJsonValue_Array _self;
  final $Res Function(BridgeAcpJsonValue_Array) _then;

/// Create a copy of BridgeAcpJsonValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? values = null,}) {
  return _then(BridgeAcpJsonValue_Array(
values: null == values ? _self._values : values // ignore: cast_nullable_to_non_nullable
as List<BridgeAcpJsonValue>,
  ));
}


}

/// @nodoc


class BridgeAcpJsonValue_Object extends BridgeAcpJsonValue {
  const BridgeAcpJsonValue_Object({required  Map<String, BridgeAcpJsonValue> fields}): _fields = fields,super._();


 final  Map<String, BridgeAcpJsonValue> _fields;
 Map<String, BridgeAcpJsonValue> get fields {
  if (_fields is EqualUnmodifiableMapView) return _fields;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_fields);
}


/// Create a copy of BridgeAcpJsonValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpJsonValue_ObjectCopyWith<BridgeAcpJsonValue_Object> get copyWith => _$BridgeAcpJsonValue_ObjectCopyWithImpl<BridgeAcpJsonValue_Object>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpJsonValue_Object&&const DeepCollectionEquality().equals(other.fields, _fields));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_fields));
}

@override
String toString() {
    return 'BridgeAcpJsonValue.object(fields: $fields)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpJsonValue_ObjectCopyWith<$Res> implements $BridgeAcpJsonValueCopyWith<$Res> {
  factory $BridgeAcpJsonValue_ObjectCopyWith(BridgeAcpJsonValue_Object value, $Res Function(BridgeAcpJsonValue_Object) _then) = _$BridgeAcpJsonValue_ObjectCopyWithImpl;
@useResult
$Res call({
 Map<String, BridgeAcpJsonValue> fields
});




}
/// @nodoc
class _$BridgeAcpJsonValue_ObjectCopyWithImpl<$Res>
    implements $BridgeAcpJsonValue_ObjectCopyWith<$Res> {
  _$BridgeAcpJsonValue_ObjectCopyWithImpl(this._self, this._then);

  final BridgeAcpJsonValue_Object _self;
  final $Res Function(BridgeAcpJsonValue_Object) _then;

/// Create a copy of BridgeAcpJsonValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fields = null,}) {
  return _then(BridgeAcpJsonValue_Object(
fields: null == fields ? _self._fields : fields // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpOpenIntent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpOpenIntent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpOpenIntent()';
}


}

/// @nodoc
class $BridgeAcpOpenIntentCopyWith<$Res>  {
$BridgeAcpOpenIntentCopyWith(BridgeAcpOpenIntent _, $Res Function(BridgeAcpOpenIntent) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpOpenIntent].
extension BridgeAcpOpenIntentPatterns on BridgeAcpOpenIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpOpenIntent_New value)?  new_,TResult Function( BridgeAcpOpenIntent_Load value)?  load,TResult Function( BridgeAcpOpenIntent_Resume value)?  resume,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpOpenIntent_New() when new_ != null:
return new_(_that);case BridgeAcpOpenIntent_Load() when load != null:
return load(_that);case BridgeAcpOpenIntent_Resume() when resume != null:
return resume(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpOpenIntent_New value)  new_,required TResult Function( BridgeAcpOpenIntent_Load value)  load,required TResult Function( BridgeAcpOpenIntent_Resume value)  resume,}){
final _that = this;
switch (_that) {
case BridgeAcpOpenIntent_New():
return new_(_that);case BridgeAcpOpenIntent_Load():
return load(_that);case BridgeAcpOpenIntent_Resume():
return resume(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpOpenIntent_New value)?  new_,TResult? Function( BridgeAcpOpenIntent_Load value)?  load,TResult? Function( BridgeAcpOpenIntent_Resume value)?  resume,}){
final _that = this;
switch (_that) {
case BridgeAcpOpenIntent_New() when new_ != null:
return new_(_that);case BridgeAcpOpenIntent_Load() when load != null:
return load(_that);case BridgeAcpOpenIntent_Resume() when resume != null:
return resume(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  new_,TResult Function( BridgeAcpRemoteSessionId sessionId)?  load,TResult Function( BridgeAcpRemoteSessionId sessionId)?  resume,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpOpenIntent_New() when new_ != null:
return new_();case BridgeAcpOpenIntent_Load() when load != null:
return load(_that.sessionId);case BridgeAcpOpenIntent_Resume() when resume != null:
return resume(_that.sessionId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  new_,required TResult Function( BridgeAcpRemoteSessionId sessionId)  load,required TResult Function( BridgeAcpRemoteSessionId sessionId)  resume,}) {final _that = this;
switch (_that) {
case BridgeAcpOpenIntent_New():
return new_();case BridgeAcpOpenIntent_Load():
return load(_that.sessionId);case BridgeAcpOpenIntent_Resume():
return resume(_that.sessionId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  new_,TResult? Function( BridgeAcpRemoteSessionId sessionId)?  load,TResult? Function( BridgeAcpRemoteSessionId sessionId)?  resume,}) {final _that = this;
switch (_that) {
case BridgeAcpOpenIntent_New() when new_ != null:
return new_();case BridgeAcpOpenIntent_Load() when load != null:
return load(_that.sessionId);case BridgeAcpOpenIntent_Resume() when resume != null:
return resume(_that.sessionId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpOpenIntent_New extends BridgeAcpOpenIntent {
  const BridgeAcpOpenIntent_New(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpOpenIntent_New);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpOpenIntent.new_()';
}


}




/// @nodoc


class BridgeAcpOpenIntent_Load extends BridgeAcpOpenIntent {
  const BridgeAcpOpenIntent_Load({required this.sessionId}): super._();


 final  BridgeAcpRemoteSessionId sessionId;

/// Create a copy of BridgeAcpOpenIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpOpenIntent_LoadCopyWith<BridgeAcpOpenIntent_Load> get copyWith => _$BridgeAcpOpenIntent_LoadCopyWithImpl<BridgeAcpOpenIntent_Load>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpOpenIntent_Load&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId);
}

@override
String toString() {
    return 'BridgeAcpOpenIntent.load(sessionId: $sessionId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpOpenIntent_LoadCopyWith<$Res> implements $BridgeAcpOpenIntentCopyWith<$Res> {
  factory $BridgeAcpOpenIntent_LoadCopyWith(BridgeAcpOpenIntent_Load value, $Res Function(BridgeAcpOpenIntent_Load) _then) = _$BridgeAcpOpenIntent_LoadCopyWithImpl;
@useResult
$Res call({
 BridgeAcpRemoteSessionId sessionId
});




}
/// @nodoc
class _$BridgeAcpOpenIntent_LoadCopyWithImpl<$Res>
    implements $BridgeAcpOpenIntent_LoadCopyWith<$Res> {
  _$BridgeAcpOpenIntent_LoadCopyWithImpl(this._self, this._then);

  final BridgeAcpOpenIntent_Load _self;
  final $Res Function(BridgeAcpOpenIntent_Load) _then;

/// Create a copy of BridgeAcpOpenIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,}) {
  return _then(BridgeAcpOpenIntent_Load(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BridgeAcpRemoteSessionId,
  ));
}


}

/// @nodoc


class BridgeAcpOpenIntent_Resume extends BridgeAcpOpenIntent {
  const BridgeAcpOpenIntent_Resume({required this.sessionId}): super._();


 final  BridgeAcpRemoteSessionId sessionId;

/// Create a copy of BridgeAcpOpenIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpOpenIntent_ResumeCopyWith<BridgeAcpOpenIntent_Resume> get copyWith => _$BridgeAcpOpenIntent_ResumeCopyWithImpl<BridgeAcpOpenIntent_Resume>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpOpenIntent_Resume&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sessionId);
}

@override
String toString() {
    return 'BridgeAcpOpenIntent.resume(sessionId: $sessionId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpOpenIntent_ResumeCopyWith<$Res> implements $BridgeAcpOpenIntentCopyWith<$Res> {
  factory $BridgeAcpOpenIntent_ResumeCopyWith(BridgeAcpOpenIntent_Resume value, $Res Function(BridgeAcpOpenIntent_Resume) _then) = _$BridgeAcpOpenIntent_ResumeCopyWithImpl;
@useResult
$Res call({
 BridgeAcpRemoteSessionId sessionId
});




}
/// @nodoc
class _$BridgeAcpOpenIntent_ResumeCopyWithImpl<$Res>
    implements $BridgeAcpOpenIntent_ResumeCopyWith<$Res> {
  _$BridgeAcpOpenIntent_ResumeCopyWithImpl(this._self, this._then);

  final BridgeAcpOpenIntent_Resume _self;
  final $Res Function(BridgeAcpOpenIntent_Resume) _then;

/// Create a copy of BridgeAcpOpenIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,}) {
  return _then(BridgeAcpOpenIntent_Resume(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BridgeAcpRemoteSessionId,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpPromptResult {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpPromptResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpPromptResult()';
}


}

/// @nodoc
class $BridgeAcpPromptResultCopyWith<$Res>  {
$BridgeAcpPromptResultCopyWith(BridgeAcpPromptResult _, $Res Function(BridgeAcpPromptResult) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpPromptResult].
extension BridgeAcpPromptResultPatterns on BridgeAcpPromptResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpPromptResult_Succeeded value)?  succeeded,TResult Function( BridgeAcpPromptResult_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpPromptResult_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeAcpPromptResult_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpPromptResult_Succeeded value)  succeeded,required TResult Function( BridgeAcpPromptResult_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeAcpPromptResult_Succeeded():
return succeeded(_that);case BridgeAcpPromptResult_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpPromptResult_Succeeded value)?  succeeded,TResult? Function( BridgeAcpPromptResult_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeAcpPromptResult_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeAcpPromptResult_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAcpPromptResponse response)?  succeeded,TResult Function( BridgeAcpBusinessFailure failure)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpPromptResult_Succeeded() when succeeded != null:
return succeeded(_that.response);case BridgeAcpPromptResult_Failed() when failed != null:
return failed(_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAcpPromptResponse response)  succeeded,required TResult Function( BridgeAcpBusinessFailure failure)  failed,}) {final _that = this;
switch (_that) {
case BridgeAcpPromptResult_Succeeded():
return succeeded(_that.response);case BridgeAcpPromptResult_Failed():
return failed(_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAcpPromptResponse response)?  succeeded,TResult? Function( BridgeAcpBusinessFailure failure)?  failed,}) {final _that = this;
switch (_that) {
case BridgeAcpPromptResult_Succeeded() when succeeded != null:
return succeeded(_that.response);case BridgeAcpPromptResult_Failed() when failed != null:
return failed(_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpPromptResult_Succeeded extends BridgeAcpPromptResult {
  const BridgeAcpPromptResult_Succeeded({required this.response}): super._();


 final  BridgeAcpPromptResponse response;

/// Create a copy of BridgeAcpPromptResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpPromptResult_SucceededCopyWith<BridgeAcpPromptResult_Succeeded> get copyWith => _$BridgeAcpPromptResult_SucceededCopyWithImpl<BridgeAcpPromptResult_Succeeded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpPromptResult_Succeeded&&(identical(other.response, response) || other.response == response));
}


@override
int get hashCode {
    return Object.hash(runtimeType,response);
}

@override
String toString() {
    return 'BridgeAcpPromptResult.succeeded(response: $response)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpPromptResult_SucceededCopyWith<$Res> implements $BridgeAcpPromptResultCopyWith<$Res> {
  factory $BridgeAcpPromptResult_SucceededCopyWith(BridgeAcpPromptResult_Succeeded value, $Res Function(BridgeAcpPromptResult_Succeeded) _then) = _$BridgeAcpPromptResult_SucceededCopyWithImpl;
@useResult
$Res call({
 BridgeAcpPromptResponse response
});




}
/// @nodoc
class _$BridgeAcpPromptResult_SucceededCopyWithImpl<$Res>
    implements $BridgeAcpPromptResult_SucceededCopyWith<$Res> {
  _$BridgeAcpPromptResult_SucceededCopyWithImpl(this._self, this._then);

  final BridgeAcpPromptResult_Succeeded _self;
  final $Res Function(BridgeAcpPromptResult_Succeeded) _then;

/// Create a copy of BridgeAcpPromptResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? response = null,}) {
  return _then(BridgeAcpPromptResult_Succeeded(
response: null == response ? _self.response : response // ignore: cast_nullable_to_non_nullable
as BridgeAcpPromptResponse,
  ));
}


}

/// @nodoc


class BridgeAcpPromptResult_Failed extends BridgeAcpPromptResult {
  const BridgeAcpPromptResult_Failed({required this.failure}): super._();


 final  BridgeAcpBusinessFailure failure;

/// Create a copy of BridgeAcpPromptResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpPromptResult_FailedCopyWith<BridgeAcpPromptResult_Failed> get copyWith => _$BridgeAcpPromptResult_FailedCopyWithImpl<BridgeAcpPromptResult_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpPromptResult_Failed&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failure);
}

@override
String toString() {
    return 'BridgeAcpPromptResult.failed(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpPromptResult_FailedCopyWith<$Res> implements $BridgeAcpPromptResultCopyWith<$Res> {
  factory $BridgeAcpPromptResult_FailedCopyWith(BridgeAcpPromptResult_Failed value, $Res Function(BridgeAcpPromptResult_Failed) _then) = _$BridgeAcpPromptResult_FailedCopyWithImpl;
@useResult
$Res call({
 BridgeAcpBusinessFailure failure
});




}
/// @nodoc
class _$BridgeAcpPromptResult_FailedCopyWithImpl<$Res>
    implements $BridgeAcpPromptResult_FailedCopyWith<$Res> {
  _$BridgeAcpPromptResult_FailedCopyWithImpl(this._self, this._then);

  final BridgeAcpPromptResult_Failed _self;
  final $Res Function(BridgeAcpPromptResult_Failed) _then;

/// Create a copy of BridgeAcpPromptResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(BridgeAcpPromptResult_Failed(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeAcpBusinessFailure,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpSelectOptions {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSelectOptions);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpSelectOptions()';
}


}

/// @nodoc
class $BridgeAcpSelectOptionsCopyWith<$Res>  {
$BridgeAcpSelectOptionsCopyWith(BridgeAcpSelectOptions _, $Res Function(BridgeAcpSelectOptions) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpSelectOptions].
extension BridgeAcpSelectOptionsPatterns on BridgeAcpSelectOptions {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpSelectOptions_Ungrouped value)?  ungrouped,TResult Function( BridgeAcpSelectOptions_Grouped value)?  grouped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpSelectOptions_Ungrouped() when ungrouped != null:
return ungrouped(_that);case BridgeAcpSelectOptions_Grouped() when grouped != null:
return grouped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpSelectOptions_Ungrouped value)  ungrouped,required TResult Function( BridgeAcpSelectOptions_Grouped value)  grouped,}){
final _that = this;
switch (_that) {
case BridgeAcpSelectOptions_Ungrouped():
return ungrouped(_that);case BridgeAcpSelectOptions_Grouped():
return grouped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpSelectOptions_Ungrouped value)?  ungrouped,TResult? Function( BridgeAcpSelectOptions_Grouped value)?  grouped,}){
final _that = this;
switch (_that) {
case BridgeAcpSelectOptions_Ungrouped() when ungrouped != null:
return ungrouped(_that);case BridgeAcpSelectOptions_Grouped() when grouped != null:
return grouped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<BridgeAcpSelectOption> options)?  ungrouped,TResult Function( List<BridgeAcpSelectGroup> groups)?  grouped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpSelectOptions_Ungrouped() when ungrouped != null:
return ungrouped(_that.options);case BridgeAcpSelectOptions_Grouped() when grouped != null:
return grouped(_that.groups);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<BridgeAcpSelectOption> options)  ungrouped,required TResult Function( List<BridgeAcpSelectGroup> groups)  grouped,}) {final _that = this;
switch (_that) {
case BridgeAcpSelectOptions_Ungrouped():
return ungrouped(_that.options);case BridgeAcpSelectOptions_Grouped():
return grouped(_that.groups);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<BridgeAcpSelectOption> options)?  ungrouped,TResult? Function( List<BridgeAcpSelectGroup> groups)?  grouped,}) {final _that = this;
switch (_that) {
case BridgeAcpSelectOptions_Ungrouped() when ungrouped != null:
return ungrouped(_that.options);case BridgeAcpSelectOptions_Grouped() when grouped != null:
return grouped(_that.groups);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpSelectOptions_Ungrouped extends BridgeAcpSelectOptions {
  const BridgeAcpSelectOptions_Ungrouped({required  List<BridgeAcpSelectOption> options}): _options = options,super._();


 final  List<BridgeAcpSelectOption> _options;
 List<BridgeAcpSelectOption> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}


/// Create a copy of BridgeAcpSelectOptions
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSelectOptions_UngroupedCopyWith<BridgeAcpSelectOptions_Ungrouped> get copyWith => _$BridgeAcpSelectOptions_UngroupedCopyWithImpl<BridgeAcpSelectOptions_Ungrouped>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSelectOptions_Ungrouped&&const DeepCollectionEquality().equals(other.options, _options));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_options));
}

@override
String toString() {
    return 'BridgeAcpSelectOptions.ungrouped(options: $options)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSelectOptions_UngroupedCopyWith<$Res> implements $BridgeAcpSelectOptionsCopyWith<$Res> {
  factory $BridgeAcpSelectOptions_UngroupedCopyWith(BridgeAcpSelectOptions_Ungrouped value, $Res Function(BridgeAcpSelectOptions_Ungrouped) _then) = _$BridgeAcpSelectOptions_UngroupedCopyWithImpl;
@useResult
$Res call({
 List<BridgeAcpSelectOption> options
});




}
/// @nodoc
class _$BridgeAcpSelectOptions_UngroupedCopyWithImpl<$Res>
    implements $BridgeAcpSelectOptions_UngroupedCopyWith<$Res> {
  _$BridgeAcpSelectOptions_UngroupedCopyWithImpl(this._self, this._then);

  final BridgeAcpSelectOptions_Ungrouped _self;
  final $Res Function(BridgeAcpSelectOptions_Ungrouped) _then;

/// Create a copy of BridgeAcpSelectOptions
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? options = null,}) {
  return _then(BridgeAcpSelectOptions_Ungrouped(
options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<BridgeAcpSelectOption>,
  ));
}


}

/// @nodoc


class BridgeAcpSelectOptions_Grouped extends BridgeAcpSelectOptions {
  const BridgeAcpSelectOptions_Grouped({required  List<BridgeAcpSelectGroup> groups}): _groups = groups,super._();


 final  List<BridgeAcpSelectGroup> _groups;
 List<BridgeAcpSelectGroup> get groups {
  if (_groups is EqualUnmodifiableListView) return _groups;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_groups);
}


/// Create a copy of BridgeAcpSelectOptions
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSelectOptions_GroupedCopyWith<BridgeAcpSelectOptions_Grouped> get copyWith => _$BridgeAcpSelectOptions_GroupedCopyWithImpl<BridgeAcpSelectOptions_Grouped>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSelectOptions_Grouped&&const DeepCollectionEquality().equals(other.groups, _groups));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_groups));
}

@override
String toString() {
    return 'BridgeAcpSelectOptions.grouped(groups: $groups)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSelectOptions_GroupedCopyWith<$Res> implements $BridgeAcpSelectOptionsCopyWith<$Res> {
  factory $BridgeAcpSelectOptions_GroupedCopyWith(BridgeAcpSelectOptions_Grouped value, $Res Function(BridgeAcpSelectOptions_Grouped) _then) = _$BridgeAcpSelectOptions_GroupedCopyWithImpl;
@useResult
$Res call({
 List<BridgeAcpSelectGroup> groups
});




}
/// @nodoc
class _$BridgeAcpSelectOptions_GroupedCopyWithImpl<$Res>
    implements $BridgeAcpSelectOptions_GroupedCopyWith<$Res> {
  _$BridgeAcpSelectOptions_GroupedCopyWithImpl(this._self, this._then);

  final BridgeAcpSelectOptions_Grouped _self;
  final $Res Function(BridgeAcpSelectOptions_Grouped) _then;

/// Create a copy of BridgeAcpSelectOptions
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? groups = null,}) {
  return _then(BridgeAcpSelectOptions_Grouped(
groups: null == groups ? _self._groups : groups // ignore: cast_nullable_to_non_nullable
as List<BridgeAcpSelectGroup>,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpSessionEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpSessionEvent()';
}


}

/// @nodoc
class $BridgeAcpSessionEventCopyWith<$Res>  {
$BridgeAcpSessionEventCopyWith(BridgeAcpSessionEvent _, $Res Function(BridgeAcpSessionEvent) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpSessionEvent].
extension BridgeAcpSessionEventPatterns on BridgeAcpSessionEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpSessionEvent_Update value)?  update,TResult Function( BridgeAcpSessionEvent_Ready value)?  ready,TResult Function( BridgeAcpSessionEvent_Failed value)?  failed,TResult Function( BridgeAcpSessionEvent_Permission value)?  permission,TResult Function( BridgeAcpSessionEvent_Configured value)?  configured,TResult Function( BridgeAcpSessionEvent_ModeSet value)?  modeSet,TResult Function( BridgeAcpSessionEvent_Completed value)?  completed,TResult Function( BridgeAcpSessionEvent_Gap value)?  gap,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpSessionEvent_Update() when update != null:
return update(_that);case BridgeAcpSessionEvent_Ready() when ready != null:
return ready(_that);case BridgeAcpSessionEvent_Failed() when failed != null:
return failed(_that);case BridgeAcpSessionEvent_Permission() when permission != null:
return permission(_that);case BridgeAcpSessionEvent_Configured() when configured != null:
return configured(_that);case BridgeAcpSessionEvent_ModeSet() when modeSet != null:
return modeSet(_that);case BridgeAcpSessionEvent_Completed() when completed != null:
return completed(_that);case BridgeAcpSessionEvent_Gap() when gap != null:
return gap(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpSessionEvent_Update value)  update,required TResult Function( BridgeAcpSessionEvent_Ready value)  ready,required TResult Function( BridgeAcpSessionEvent_Failed value)  failed,required TResult Function( BridgeAcpSessionEvent_Permission value)  permission,required TResult Function( BridgeAcpSessionEvent_Configured value)  configured,required TResult Function( BridgeAcpSessionEvent_ModeSet value)  modeSet,required TResult Function( BridgeAcpSessionEvent_Completed value)  completed,required TResult Function( BridgeAcpSessionEvent_Gap value)  gap,}){
final _that = this;
switch (_that) {
case BridgeAcpSessionEvent_Update():
return update(_that);case BridgeAcpSessionEvent_Ready():
return ready(_that);case BridgeAcpSessionEvent_Failed():
return failed(_that);case BridgeAcpSessionEvent_Permission():
return permission(_that);case BridgeAcpSessionEvent_Configured():
return configured(_that);case BridgeAcpSessionEvent_ModeSet():
return modeSet(_that);case BridgeAcpSessionEvent_Completed():
return completed(_that);case BridgeAcpSessionEvent_Gap():
return gap(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpSessionEvent_Update value)?  update,TResult? Function( BridgeAcpSessionEvent_Ready value)?  ready,TResult? Function( BridgeAcpSessionEvent_Failed value)?  failed,TResult? Function( BridgeAcpSessionEvent_Permission value)?  permission,TResult? Function( BridgeAcpSessionEvent_Configured value)?  configured,TResult? Function( BridgeAcpSessionEvent_ModeSet value)?  modeSet,TResult? Function( BridgeAcpSessionEvent_Completed value)?  completed,TResult? Function( BridgeAcpSessionEvent_Gap value)?  gap,}){
final _that = this;
switch (_that) {
case BridgeAcpSessionEvent_Update() when update != null:
return update(_that);case BridgeAcpSessionEvent_Ready() when ready != null:
return ready(_that);case BridgeAcpSessionEvent_Failed() when failed != null:
return failed(_that);case BridgeAcpSessionEvent_Permission() when permission != null:
return permission(_that);case BridgeAcpSessionEvent_Configured() when configured != null:
return configured(_that);case BridgeAcpSessionEvent_ModeSet() when modeSet != null:
return modeSet(_that);case BridgeAcpSessionEvent_Completed() when completed != null:
return completed(_that);case BridgeAcpSessionEvent_Gap() when gap != null:
return gap(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAcpSessionNotification update)?  update,TResult Function( BridgeAcpNewSessionResponse response)?  ready,TResult Function( BridgeAcpBusinessFailure failure)?  failed,TResult Function( BridgeAcpPermissionId id,  BridgeAcpPermissionRequest request)?  permission,TResult Function( List<BridgeAcpConfigOption> configOptions,  Map<String, BridgeAcpJsonValue>? meta)?  configured,TResult Function( BridgeAcpModeId modeId)?  modeSet,TResult Function( BridgeAcpCompletedRun completed)?  completed,TResult Function( BridgeAcpObservationGap gap)?  gap,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpSessionEvent_Update() when update != null:
return update(_that.update);case BridgeAcpSessionEvent_Ready() when ready != null:
return ready(_that.response);case BridgeAcpSessionEvent_Failed() when failed != null:
return failed(_that.failure);case BridgeAcpSessionEvent_Permission() when permission != null:
return permission(_that.id,_that.request);case BridgeAcpSessionEvent_Configured() when configured != null:
return configured(_that.configOptions,_that.meta);case BridgeAcpSessionEvent_ModeSet() when modeSet != null:
return modeSet(_that.modeId);case BridgeAcpSessionEvent_Completed() when completed != null:
return completed(_that.completed);case BridgeAcpSessionEvent_Gap() when gap != null:
return gap(_that.gap);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAcpSessionNotification update)  update,required TResult Function( BridgeAcpNewSessionResponse response)  ready,required TResult Function( BridgeAcpBusinessFailure failure)  failed,required TResult Function( BridgeAcpPermissionId id,  BridgeAcpPermissionRequest request)  permission,required TResult Function( List<BridgeAcpConfigOption> configOptions,  Map<String, BridgeAcpJsonValue>? meta)  configured,required TResult Function( BridgeAcpModeId modeId)  modeSet,required TResult Function( BridgeAcpCompletedRun completed)  completed,required TResult Function( BridgeAcpObservationGap gap)  gap,}) {final _that = this;
switch (_that) {
case BridgeAcpSessionEvent_Update():
return update(_that.update);case BridgeAcpSessionEvent_Ready():
return ready(_that.response);case BridgeAcpSessionEvent_Failed():
return failed(_that.failure);case BridgeAcpSessionEvent_Permission():
return permission(_that.id,_that.request);case BridgeAcpSessionEvent_Configured():
return configured(_that.configOptions,_that.meta);case BridgeAcpSessionEvent_ModeSet():
return modeSet(_that.modeId);case BridgeAcpSessionEvent_Completed():
return completed(_that.completed);case BridgeAcpSessionEvent_Gap():
return gap(_that.gap);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAcpSessionNotification update)?  update,TResult? Function( BridgeAcpNewSessionResponse response)?  ready,TResult? Function( BridgeAcpBusinessFailure failure)?  failed,TResult? Function( BridgeAcpPermissionId id,  BridgeAcpPermissionRequest request)?  permission,TResult? Function( List<BridgeAcpConfigOption> configOptions,  Map<String, BridgeAcpJsonValue>? meta)?  configured,TResult? Function( BridgeAcpModeId modeId)?  modeSet,TResult? Function( BridgeAcpCompletedRun completed)?  completed,TResult? Function( BridgeAcpObservationGap gap)?  gap,}) {final _that = this;
switch (_that) {
case BridgeAcpSessionEvent_Update() when update != null:
return update(_that.update);case BridgeAcpSessionEvent_Ready() when ready != null:
return ready(_that.response);case BridgeAcpSessionEvent_Failed() when failed != null:
return failed(_that.failure);case BridgeAcpSessionEvent_Permission() when permission != null:
return permission(_that.id,_that.request);case BridgeAcpSessionEvent_Configured() when configured != null:
return configured(_that.configOptions,_that.meta);case BridgeAcpSessionEvent_ModeSet() when modeSet != null:
return modeSet(_that.modeId);case BridgeAcpSessionEvent_Completed() when completed != null:
return completed(_that.completed);case BridgeAcpSessionEvent_Gap() when gap != null:
return gap(_that.gap);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpSessionEvent_Update extends BridgeAcpSessionEvent {
  const BridgeAcpSessionEvent_Update({required this.update}): super._();


 final  BridgeAcpSessionNotification update;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionEvent_UpdateCopyWith<BridgeAcpSessionEvent_Update> get copyWith => _$BridgeAcpSessionEvent_UpdateCopyWithImpl<BridgeAcpSessionEvent_Update>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionEvent_Update&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,update);
}

@override
String toString() {
    return 'BridgeAcpSessionEvent.update(update: $update)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionEvent_UpdateCopyWith<$Res> implements $BridgeAcpSessionEventCopyWith<$Res> {
  factory $BridgeAcpSessionEvent_UpdateCopyWith(BridgeAcpSessionEvent_Update value, $Res Function(BridgeAcpSessionEvent_Update) _then) = _$BridgeAcpSessionEvent_UpdateCopyWithImpl;
@useResult
$Res call({
 BridgeAcpSessionNotification update
});




}
/// @nodoc
class _$BridgeAcpSessionEvent_UpdateCopyWithImpl<$Res>
    implements $BridgeAcpSessionEvent_UpdateCopyWith<$Res> {
  _$BridgeAcpSessionEvent_UpdateCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionEvent_Update _self;
  final $Res Function(BridgeAcpSessionEvent_Update) _then;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? update = null,}) {
  return _then(BridgeAcpSessionEvent_Update(
update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as BridgeAcpSessionNotification,
  ));
}


}

/// @nodoc


class BridgeAcpSessionEvent_Ready extends BridgeAcpSessionEvent {
  const BridgeAcpSessionEvent_Ready({required this.response}): super._();


 final  BridgeAcpNewSessionResponse response;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionEvent_ReadyCopyWith<BridgeAcpSessionEvent_Ready> get copyWith => _$BridgeAcpSessionEvent_ReadyCopyWithImpl<BridgeAcpSessionEvent_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionEvent_Ready&&(identical(other.response, response) || other.response == response));
}


@override
int get hashCode {
    return Object.hash(runtimeType,response);
}

@override
String toString() {
    return 'BridgeAcpSessionEvent.ready(response: $response)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionEvent_ReadyCopyWith<$Res> implements $BridgeAcpSessionEventCopyWith<$Res> {
  factory $BridgeAcpSessionEvent_ReadyCopyWith(BridgeAcpSessionEvent_Ready value, $Res Function(BridgeAcpSessionEvent_Ready) _then) = _$BridgeAcpSessionEvent_ReadyCopyWithImpl;
@useResult
$Res call({
 BridgeAcpNewSessionResponse response
});




}
/// @nodoc
class _$BridgeAcpSessionEvent_ReadyCopyWithImpl<$Res>
    implements $BridgeAcpSessionEvent_ReadyCopyWith<$Res> {
  _$BridgeAcpSessionEvent_ReadyCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionEvent_Ready _self;
  final $Res Function(BridgeAcpSessionEvent_Ready) _then;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? response = null,}) {
  return _then(BridgeAcpSessionEvent_Ready(
response: null == response ? _self.response : response // ignore: cast_nullable_to_non_nullable
as BridgeAcpNewSessionResponse,
  ));
}


}

/// @nodoc


class BridgeAcpSessionEvent_Failed extends BridgeAcpSessionEvent {
  const BridgeAcpSessionEvent_Failed({required this.failure}): super._();


 final  BridgeAcpBusinessFailure failure;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionEvent_FailedCopyWith<BridgeAcpSessionEvent_Failed> get copyWith => _$BridgeAcpSessionEvent_FailedCopyWithImpl<BridgeAcpSessionEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionEvent_Failed&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failure);
}

@override
String toString() {
    return 'BridgeAcpSessionEvent.failed(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionEvent_FailedCopyWith<$Res> implements $BridgeAcpSessionEventCopyWith<$Res> {
  factory $BridgeAcpSessionEvent_FailedCopyWith(BridgeAcpSessionEvent_Failed value, $Res Function(BridgeAcpSessionEvent_Failed) _then) = _$BridgeAcpSessionEvent_FailedCopyWithImpl;
@useResult
$Res call({
 BridgeAcpBusinessFailure failure
});




}
/// @nodoc
class _$BridgeAcpSessionEvent_FailedCopyWithImpl<$Res>
    implements $BridgeAcpSessionEvent_FailedCopyWith<$Res> {
  _$BridgeAcpSessionEvent_FailedCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionEvent_Failed _self;
  final $Res Function(BridgeAcpSessionEvent_Failed) _then;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(BridgeAcpSessionEvent_Failed(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeAcpBusinessFailure,
  ));
}


}

/// @nodoc


class BridgeAcpSessionEvent_Permission extends BridgeAcpSessionEvent {
  const BridgeAcpSessionEvent_Permission({required this.id, required this.request}): super._();


 final  BridgeAcpPermissionId id;
 final  BridgeAcpPermissionRequest request;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionEvent_PermissionCopyWith<BridgeAcpSessionEvent_Permission> get copyWith => _$BridgeAcpSessionEvent_PermissionCopyWithImpl<BridgeAcpSessionEvent_Permission>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionEvent_Permission&&(identical(other.id, id) || other.id == id)&&(identical(other.request, request) || other.request == request));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,request);
}

@override
String toString() {
    return 'BridgeAcpSessionEvent.permission(id: $id, request: $request)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionEvent_PermissionCopyWith<$Res> implements $BridgeAcpSessionEventCopyWith<$Res> {
  factory $BridgeAcpSessionEvent_PermissionCopyWith(BridgeAcpSessionEvent_Permission value, $Res Function(BridgeAcpSessionEvent_Permission) _then) = _$BridgeAcpSessionEvent_PermissionCopyWithImpl;
@useResult
$Res call({
 BridgeAcpPermissionId id, BridgeAcpPermissionRequest request
});




}
/// @nodoc
class _$BridgeAcpSessionEvent_PermissionCopyWithImpl<$Res>
    implements $BridgeAcpSessionEvent_PermissionCopyWith<$Res> {
  _$BridgeAcpSessionEvent_PermissionCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionEvent_Permission _self;
  final $Res Function(BridgeAcpSessionEvent_Permission) _then;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? request = null,}) {
  return _then(BridgeAcpSessionEvent_Permission(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as BridgeAcpPermissionId,request: null == request ? _self.request : request // ignore: cast_nullable_to_non_nullable
as BridgeAcpPermissionRequest,
  ));
}


}

/// @nodoc


class BridgeAcpSessionEvent_Configured extends BridgeAcpSessionEvent {
  const BridgeAcpSessionEvent_Configured({required  List<BridgeAcpConfigOption> configOptions,  Map<String, BridgeAcpJsonValue>? meta}): _configOptions = configOptions,_meta = meta,super._();


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


/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionEvent_ConfiguredCopyWith<BridgeAcpSessionEvent_Configured> get copyWith => _$BridgeAcpSessionEvent_ConfiguredCopyWithImpl<BridgeAcpSessionEvent_Configured>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionEvent_Configured&&const DeepCollectionEquality().equals(other.configOptions, _configOptions)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_configOptions),const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpSessionEvent.configured(configOptions: $configOptions, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionEvent_ConfiguredCopyWith<$Res> implements $BridgeAcpSessionEventCopyWith<$Res> {
  factory $BridgeAcpSessionEvent_ConfiguredCopyWith(BridgeAcpSessionEvent_Configured value, $Res Function(BridgeAcpSessionEvent_Configured) _then) = _$BridgeAcpSessionEvent_ConfiguredCopyWithImpl;
@useResult
$Res call({
 List<BridgeAcpConfigOption> configOptions, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpSessionEvent_ConfiguredCopyWithImpl<$Res>
    implements $BridgeAcpSessionEvent_ConfiguredCopyWith<$Res> {
  _$BridgeAcpSessionEvent_ConfiguredCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionEvent_Configured _self;
  final $Res Function(BridgeAcpSessionEvent_Configured) _then;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? configOptions = null,Object? meta = freezed,}) {
  return _then(BridgeAcpSessionEvent_Configured(
configOptions: null == configOptions ? _self._configOptions : configOptions // ignore: cast_nullable_to_non_nullable
as List<BridgeAcpConfigOption>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpSessionEvent_ModeSet extends BridgeAcpSessionEvent {
  const BridgeAcpSessionEvent_ModeSet({required this.modeId}): super._();


 final  BridgeAcpModeId modeId;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionEvent_ModeSetCopyWith<BridgeAcpSessionEvent_ModeSet> get copyWith => _$BridgeAcpSessionEvent_ModeSetCopyWithImpl<BridgeAcpSessionEvent_ModeSet>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionEvent_ModeSet&&(identical(other.modeId, modeId) || other.modeId == modeId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modeId);
}

@override
String toString() {
    return 'BridgeAcpSessionEvent.modeSet(modeId: $modeId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionEvent_ModeSetCopyWith<$Res> implements $BridgeAcpSessionEventCopyWith<$Res> {
  factory $BridgeAcpSessionEvent_ModeSetCopyWith(BridgeAcpSessionEvent_ModeSet value, $Res Function(BridgeAcpSessionEvent_ModeSet) _then) = _$BridgeAcpSessionEvent_ModeSetCopyWithImpl;
@useResult
$Res call({
 BridgeAcpModeId modeId
});




}
/// @nodoc
class _$BridgeAcpSessionEvent_ModeSetCopyWithImpl<$Res>
    implements $BridgeAcpSessionEvent_ModeSetCopyWith<$Res> {
  _$BridgeAcpSessionEvent_ModeSetCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionEvent_ModeSet _self;
  final $Res Function(BridgeAcpSessionEvent_ModeSet) _then;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? modeId = null,}) {
  return _then(BridgeAcpSessionEvent_ModeSet(
modeId: null == modeId ? _self.modeId : modeId // ignore: cast_nullable_to_non_nullable
as BridgeAcpModeId,
  ));
}


}

/// @nodoc


class BridgeAcpSessionEvent_Completed extends BridgeAcpSessionEvent {
  const BridgeAcpSessionEvent_Completed({required this.completed}): super._();


 final  BridgeAcpCompletedRun completed;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionEvent_CompletedCopyWith<BridgeAcpSessionEvent_Completed> get copyWith => _$BridgeAcpSessionEvent_CompletedCopyWithImpl<BridgeAcpSessionEvent_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionEvent_Completed&&(identical(other.completed, completed) || other.completed == completed));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completed);
}

@override
String toString() {
    return 'BridgeAcpSessionEvent.completed(completed: $completed)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionEvent_CompletedCopyWith<$Res> implements $BridgeAcpSessionEventCopyWith<$Res> {
  factory $BridgeAcpSessionEvent_CompletedCopyWith(BridgeAcpSessionEvent_Completed value, $Res Function(BridgeAcpSessionEvent_Completed) _then) = _$BridgeAcpSessionEvent_CompletedCopyWithImpl;
@useResult
$Res call({
 BridgeAcpCompletedRun completed
});




}
/// @nodoc
class _$BridgeAcpSessionEvent_CompletedCopyWithImpl<$Res>
    implements $BridgeAcpSessionEvent_CompletedCopyWith<$Res> {
  _$BridgeAcpSessionEvent_CompletedCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionEvent_Completed _self;
  final $Res Function(BridgeAcpSessionEvent_Completed) _then;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completed = null,}) {
  return _then(BridgeAcpSessionEvent_Completed(
completed: null == completed ? _self.completed : completed // ignore: cast_nullable_to_non_nullable
as BridgeAcpCompletedRun,
  ));
}


}

/// @nodoc


class BridgeAcpSessionEvent_Gap extends BridgeAcpSessionEvent {
  const BridgeAcpSessionEvent_Gap({required this.gap}): super._();


 final  BridgeAcpObservationGap gap;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionEvent_GapCopyWith<BridgeAcpSessionEvent_Gap> get copyWith => _$BridgeAcpSessionEvent_GapCopyWithImpl<BridgeAcpSessionEvent_Gap>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionEvent_Gap&&(identical(other.gap, gap) || other.gap == gap));
}


@override
int get hashCode {
    return Object.hash(runtimeType,gap);
}

@override
String toString() {
    return 'BridgeAcpSessionEvent.gap(gap: $gap)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionEvent_GapCopyWith<$Res> implements $BridgeAcpSessionEventCopyWith<$Res> {
  factory $BridgeAcpSessionEvent_GapCopyWith(BridgeAcpSessionEvent_Gap value, $Res Function(BridgeAcpSessionEvent_Gap) _then) = _$BridgeAcpSessionEvent_GapCopyWithImpl;
@useResult
$Res call({
 BridgeAcpObservationGap gap
});




}
/// @nodoc
class _$BridgeAcpSessionEvent_GapCopyWithImpl<$Res>
    implements $BridgeAcpSessionEvent_GapCopyWith<$Res> {
  _$BridgeAcpSessionEvent_GapCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionEvent_Gap _self;
  final $Res Function(BridgeAcpSessionEvent_Gap) _then;

/// Create a copy of BridgeAcpSessionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? gap = null,}) {
  return _then(BridgeAcpSessionEvent_Gap(
gap: null == gap ? _self.gap : gap // ignore: cast_nullable_to_non_nullable
as BridgeAcpObservationGap,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpSessionFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpSessionFrame()';
}


}

/// @nodoc
class $BridgeAcpSessionFrameCopyWith<$Res>  {
$BridgeAcpSessionFrameCopyWith(BridgeAcpSessionFrame _, $Res Function(BridgeAcpSessionFrame) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpSessionFrame].
extension BridgeAcpSessionFramePatterns on BridgeAcpSessionFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpSessionFrame_Accepted value)?  accepted,TResult Function( BridgeAcpSessionFrame_Settled value)?  settled,TResult Function( BridgeAcpSessionFrame_Event value)?  event,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpSessionFrame_Accepted() when accepted != null:
return accepted(_that);case BridgeAcpSessionFrame_Settled() when settled != null:
return settled(_that);case BridgeAcpSessionFrame_Event() when event != null:
return event(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpSessionFrame_Accepted value)  accepted,required TResult Function( BridgeAcpSessionFrame_Settled value)  settled,required TResult Function( BridgeAcpSessionFrame_Event value)  event,}){
final _that = this;
switch (_that) {
case BridgeAcpSessionFrame_Accepted():
return accepted(_that);case BridgeAcpSessionFrame_Settled():
return settled(_that);case BridgeAcpSessionFrame_Event():
return event(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpSessionFrame_Accepted value)?  accepted,TResult? Function( BridgeAcpSessionFrame_Settled value)?  settled,TResult? Function( BridgeAcpSessionFrame_Event value)?  event,}){
final _that = this;
switch (_that) {
case BridgeAcpSessionFrame_Accepted() when accepted != null:
return accepted(_that);case BridgeAcpSessionFrame_Settled() when settled != null:
return settled(_that);case BridgeAcpSessionFrame_Event() when event != null:
return event(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAcpSessionTarget target,  bool hasObservation)?  accepted,TResult Function( BridgeAcpSettlement result)?  settled,TResult Function( BridgeAcpSessionEvent event)?  event,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpSessionFrame_Accepted() when accepted != null:
return accepted(_that.target,_that.hasObservation);case BridgeAcpSessionFrame_Settled() when settled != null:
return settled(_that.result);case BridgeAcpSessionFrame_Event() when event != null:
return event(_that.event);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAcpSessionTarget target,  bool hasObservation)  accepted,required TResult Function( BridgeAcpSettlement result)  settled,required TResult Function( BridgeAcpSessionEvent event)  event,}) {final _that = this;
switch (_that) {
case BridgeAcpSessionFrame_Accepted():
return accepted(_that.target,_that.hasObservation);case BridgeAcpSessionFrame_Settled():
return settled(_that.result);case BridgeAcpSessionFrame_Event():
return event(_that.event);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAcpSessionTarget target,  bool hasObservation)?  accepted,TResult? Function( BridgeAcpSettlement result)?  settled,TResult? Function( BridgeAcpSessionEvent event)?  event,}) {final _that = this;
switch (_that) {
case BridgeAcpSessionFrame_Accepted() when accepted != null:
return accepted(_that.target,_that.hasObservation);case BridgeAcpSessionFrame_Settled() when settled != null:
return settled(_that.result);case BridgeAcpSessionFrame_Event() when event != null:
return event(_that.event);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpSessionFrame_Accepted extends BridgeAcpSessionFrame {
  const BridgeAcpSessionFrame_Accepted({required this.target, required this.hasObservation}): super._();


 final  BridgeAcpSessionTarget target;
 final  bool hasObservation;

/// Create a copy of BridgeAcpSessionFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionFrame_AcceptedCopyWith<BridgeAcpSessionFrame_Accepted> get copyWith => _$BridgeAcpSessionFrame_AcceptedCopyWithImpl<BridgeAcpSessionFrame_Accepted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionFrame_Accepted&&(identical(other.target, target) || other.target == target)&&(identical(other.hasObservation, hasObservation) || other.hasObservation == hasObservation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,target,hasObservation);
}

@override
String toString() {
    return 'BridgeAcpSessionFrame.accepted(target: $target, hasObservation: $hasObservation)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionFrame_AcceptedCopyWith<$Res> implements $BridgeAcpSessionFrameCopyWith<$Res> {
  factory $BridgeAcpSessionFrame_AcceptedCopyWith(BridgeAcpSessionFrame_Accepted value, $Res Function(BridgeAcpSessionFrame_Accepted) _then) = _$BridgeAcpSessionFrame_AcceptedCopyWithImpl;
@useResult
$Res call({
 BridgeAcpSessionTarget target, bool hasObservation
});




}
/// @nodoc
class _$BridgeAcpSessionFrame_AcceptedCopyWithImpl<$Res>
    implements $BridgeAcpSessionFrame_AcceptedCopyWith<$Res> {
  _$BridgeAcpSessionFrame_AcceptedCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionFrame_Accepted _self;
  final $Res Function(BridgeAcpSessionFrame_Accepted) _then;

/// Create a copy of BridgeAcpSessionFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? target = null,Object? hasObservation = null,}) {
  return _then(BridgeAcpSessionFrame_Accepted(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as BridgeAcpSessionTarget,hasObservation: null == hasObservation ? _self.hasObservation : hasObservation // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgeAcpSessionFrame_Settled extends BridgeAcpSessionFrame {
  const BridgeAcpSessionFrame_Settled({required this.result}): super._();


 final  BridgeAcpSettlement result;

/// Create a copy of BridgeAcpSessionFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionFrame_SettledCopyWith<BridgeAcpSessionFrame_Settled> get copyWith => _$BridgeAcpSessionFrame_SettledCopyWithImpl<BridgeAcpSessionFrame_Settled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionFrame_Settled&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,result);
}

@override
String toString() {
    return 'BridgeAcpSessionFrame.settled(result: $result)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionFrame_SettledCopyWith<$Res> implements $BridgeAcpSessionFrameCopyWith<$Res> {
  factory $BridgeAcpSessionFrame_SettledCopyWith(BridgeAcpSessionFrame_Settled value, $Res Function(BridgeAcpSessionFrame_Settled) _then) = _$BridgeAcpSessionFrame_SettledCopyWithImpl;
@useResult
$Res call({
 BridgeAcpSettlement result
});


$BridgeAcpSettlementCopyWith<$Res> get result;

}
/// @nodoc
class _$BridgeAcpSessionFrame_SettledCopyWithImpl<$Res>
    implements $BridgeAcpSessionFrame_SettledCopyWith<$Res> {
  _$BridgeAcpSessionFrame_SettledCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionFrame_Settled _self;
  final $Res Function(BridgeAcpSessionFrame_Settled) _then;

/// Create a copy of BridgeAcpSessionFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? result = null,}) {
  return _then(BridgeAcpSessionFrame_Settled(
result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as BridgeAcpSettlement,
  ));
}

/// Create a copy of BridgeAcpSessionFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpSettlementCopyWith<$Res> get result {

  return $BridgeAcpSettlementCopyWith<$Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

/// @nodoc


class BridgeAcpSessionFrame_Event extends BridgeAcpSessionFrame {
  const BridgeAcpSessionFrame_Event({required this.event}): super._();


 final  BridgeAcpSessionEvent event;

/// Create a copy of BridgeAcpSessionFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSessionFrame_EventCopyWith<BridgeAcpSessionFrame_Event> get copyWith => _$BridgeAcpSessionFrame_EventCopyWithImpl<BridgeAcpSessionFrame_Event>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSessionFrame_Event&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,event);
}

@override
String toString() {
    return 'BridgeAcpSessionFrame.event(event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSessionFrame_EventCopyWith<$Res> implements $BridgeAcpSessionFrameCopyWith<$Res> {
  factory $BridgeAcpSessionFrame_EventCopyWith(BridgeAcpSessionFrame_Event value, $Res Function(BridgeAcpSessionFrame_Event) _then) = _$BridgeAcpSessionFrame_EventCopyWithImpl;
@useResult
$Res call({
 BridgeAcpSessionEvent event
});


$BridgeAcpSessionEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgeAcpSessionFrame_EventCopyWithImpl<$Res>
    implements $BridgeAcpSessionFrame_EventCopyWith<$Res> {
  _$BridgeAcpSessionFrame_EventCopyWithImpl(this._self, this._then);

  final BridgeAcpSessionFrame_Event _self;
  final $Res Function(BridgeAcpSessionFrame_Event) _then;

/// Create a copy of BridgeAcpSessionFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? event = null,}) {
  return _then(BridgeAcpSessionFrame_Event(
event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgeAcpSessionEvent,
  ));
}

/// Create a copy of BridgeAcpSessionFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpSessionEventCopyWith<$Res> get event {

  return $BridgeAcpSessionEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc
mixin _$BridgeAcpSettlement {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSettlement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpSettlement()';
}


}

/// @nodoc
class $BridgeAcpSettlementCopyWith<$Res>  {
$BridgeAcpSettlementCopyWith(BridgeAcpSettlement _, $Res Function(BridgeAcpSettlement) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpSettlement].
extension BridgeAcpSettlementPatterns on BridgeAcpSettlement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpSettlement_Succeeded value)?  succeeded,TResult Function( BridgeAcpSettlement_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpSettlement_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeAcpSettlement_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpSettlement_Succeeded value)  succeeded,required TResult Function( BridgeAcpSettlement_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeAcpSettlement_Succeeded():
return succeeded(_that);case BridgeAcpSettlement_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpSettlement_Succeeded value)?  succeeded,TResult? Function( BridgeAcpSettlement_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeAcpSettlement_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeAcpSettlement_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  succeeded,TResult Function( BridgeAcpBusinessFailure failure)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpSettlement_Succeeded() when succeeded != null:
return succeeded();case BridgeAcpSettlement_Failed() when failed != null:
return failed(_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  succeeded,required TResult Function( BridgeAcpBusinessFailure failure)  failed,}) {final _that = this;
switch (_that) {
case BridgeAcpSettlement_Succeeded():
return succeeded();case BridgeAcpSettlement_Failed():
return failed(_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  succeeded,TResult? Function( BridgeAcpBusinessFailure failure)?  failed,}) {final _that = this;
switch (_that) {
case BridgeAcpSettlement_Succeeded() when succeeded != null:
return succeeded();case BridgeAcpSettlement_Failed() when failed != null:
return failed(_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpSettlement_Succeeded extends BridgeAcpSettlement {
  const BridgeAcpSettlement_Succeeded(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSettlement_Succeeded);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpSettlement.succeeded()';
}


}




/// @nodoc


class BridgeAcpSettlement_Failed extends BridgeAcpSettlement {
  const BridgeAcpSettlement_Failed({required this.failure}): super._();


 final  BridgeAcpBusinessFailure failure;

/// Create a copy of BridgeAcpSettlement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpSettlement_FailedCopyWith<BridgeAcpSettlement_Failed> get copyWith => _$BridgeAcpSettlement_FailedCopyWithImpl<BridgeAcpSettlement_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpSettlement_Failed&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failure);
}

@override
String toString() {
    return 'BridgeAcpSettlement.failed(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpSettlement_FailedCopyWith<$Res> implements $BridgeAcpSettlementCopyWith<$Res> {
  factory $BridgeAcpSettlement_FailedCopyWith(BridgeAcpSettlement_Failed value, $Res Function(BridgeAcpSettlement_Failed) _then) = _$BridgeAcpSettlement_FailedCopyWithImpl;
@useResult
$Res call({
 BridgeAcpBusinessFailure failure
});




}
/// @nodoc
class _$BridgeAcpSettlement_FailedCopyWithImpl<$Res>
    implements $BridgeAcpSettlement_FailedCopyWith<$Res> {
  _$BridgeAcpSettlement_FailedCopyWithImpl(this._self, this._then);

  final BridgeAcpSettlement_Failed _self;
  final $Res Function(BridgeAcpSettlement_Failed) _then;

/// Create a copy of BridgeAcpSettlement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(BridgeAcpSettlement_Failed(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeAcpBusinessFailure,
  ));
}


}

// dart format on
