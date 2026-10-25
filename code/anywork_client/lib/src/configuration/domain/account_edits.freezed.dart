// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_edits.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FieldEdit<T> {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldEdit<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'FieldEdit<$T>()';
}


}

/// @nodoc
class $FieldEditCopyWith<T,$Res>  {
$FieldEditCopyWith(FieldEdit<T> _, $Res Function(FieldEdit<T>) __);
}


/// Adds pattern-matching-related methods to [FieldEdit].
extension FieldEditPatterns<T> on FieldEdit<T> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( KeepField<T> value)?  keep,TResult Function( SetField<T> value)?  set,required TResult orElse(),}){
final _that = this;
switch (_that) {
case KeepField() when keep != null:
return keep(_that);case SetField() when set != null:
return set(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( KeepField<T> value)  keep,required TResult Function( SetField<T> value)  set,}){
final _that = this;
switch (_that) {
case KeepField():
return keep(_that);case SetField():
return set(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( KeepField<T> value)?  keep,TResult? Function( SetField<T> value)?  set,}){
final _that = this;
switch (_that) {
case KeepField() when keep != null:
return keep(_that);case SetField() when set != null:
return set(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  keep,TResult Function( T value)?  set,required TResult orElse(),}) {final _that = this;
switch (_that) {
case KeepField() when keep != null:
return keep();case SetField() when set != null:
return set(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  keep,required TResult Function( T value)  set,}) {final _that = this;
switch (_that) {
case KeepField():
return keep();case SetField():
return set(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  keep,TResult? Function( T value)?  set,}) {final _that = this;
switch (_that) {
case KeepField() when keep != null:
return keep();case SetField() when set != null:
return set(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class KeepField<T> implements FieldEdit<T> {
  const KeepField();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is KeepField<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'FieldEdit<$T>.keep()';
}


}




/// @nodoc


class SetField<T> implements FieldEdit<T> {
  const SetField(this.value);


 final  T value;

/// Create a copy of FieldEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetFieldCopyWith<T, SetField<T>> get copyWith => _$SetFieldCopyWithImpl<T, SetField<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SetField<T>&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(value));
}

@override
String toString() {
    return 'FieldEdit<$T>.set(value: $value)';
}


}

/// @nodoc
abstract mixin class $SetFieldCopyWith<T,$Res> implements $FieldEditCopyWith<T, $Res> {
  factory $SetFieldCopyWith(SetField<T> value, $Res Function(SetField<T>) _then) = _$SetFieldCopyWithImpl;
@useResult
$Res call({
 T value
});




}
/// @nodoc
class _$SetFieldCopyWithImpl<T,$Res>
    implements $SetFieldCopyWith<T, $Res> {
  _$SetFieldCopyWithImpl(this._self, this._then);

  final SetField<T> _self;
  final $Res Function(SetField<T>) _then;

/// Create a copy of FieldEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(SetField<T>(
freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,
  ));
}


}

/// @nodoc
mixin _$AccountSecretUpdate {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountSecretUpdate);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AccountSecretUpdateCopyWith<$Res>  {
$AccountSecretUpdateCopyWith(AccountSecretUpdate _, $Res Function(AccountSecretUpdate) __);
}


/// Adds pattern-matching-related methods to [AccountSecretUpdate].
extension AccountSecretUpdatePatterns on AccountSecretUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PreserveAccountSecret value)?  preserve,TResult Function( ReplaceAccountSecret value)?  replace,TResult Function( ClearAccountSecret value)?  clear,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PreserveAccountSecret() when preserve != null:
return preserve(_that);case ReplaceAccountSecret() when replace != null:
return replace(_that);case ClearAccountSecret() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PreserveAccountSecret value)  preserve,required TResult Function( ReplaceAccountSecret value)  replace,required TResult Function( ClearAccountSecret value)  clear,}){
final _that = this;
switch (_that) {
case PreserveAccountSecret():
return preserve(_that);case ReplaceAccountSecret():
return replace(_that);case ClearAccountSecret():
return clear(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PreserveAccountSecret value)?  preserve,TResult? Function( ReplaceAccountSecret value)?  replace,TResult? Function( ClearAccountSecret value)?  clear,}){
final _that = this;
switch (_that) {
case PreserveAccountSecret() when preserve != null:
return preserve(_that);case ReplaceAccountSecret() when replace != null:
return replace(_that);case ClearAccountSecret() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  preserve,TResult Function( String value)?  replace,TResult Function()?  clear,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PreserveAccountSecret() when preserve != null:
return preserve();case ReplaceAccountSecret() when replace != null:
return replace(_that.value);case ClearAccountSecret() when clear != null:
return clear();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  preserve,required TResult Function( String value)  replace,required TResult Function()  clear,}) {final _that = this;
switch (_that) {
case PreserveAccountSecret():
return preserve();case ReplaceAccountSecret():
return replace(_that.value);case ClearAccountSecret():
return clear();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  preserve,TResult? Function( String value)?  replace,TResult? Function()?  clear,}) {final _that = this;
switch (_that) {
case PreserveAccountSecret() when preserve != null:
return preserve();case ReplaceAccountSecret() when replace != null:
return replace(_that.value);case ClearAccountSecret() when clear != null:
return clear();case _:
  return null;

}
}

}

/// @nodoc


class PreserveAccountSecret implements AccountSecretUpdate {
  const PreserveAccountSecret();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PreserveAccountSecret);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class ReplaceAccountSecret implements AccountSecretUpdate {
  const ReplaceAccountSecret(this.value);


 final  String value;

/// Create a copy of AccountSecretUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplaceAccountSecretCopyWith<ReplaceAccountSecret> get copyWith => _$ReplaceAccountSecretCopyWithImpl<ReplaceAccountSecret>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplaceAccountSecret&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $ReplaceAccountSecretCopyWith<$Res> implements $AccountSecretUpdateCopyWith<$Res> {
  factory $ReplaceAccountSecretCopyWith(ReplaceAccountSecret value, $Res Function(ReplaceAccountSecret) _then) = _$ReplaceAccountSecretCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$ReplaceAccountSecretCopyWithImpl<$Res>
    implements $ReplaceAccountSecretCopyWith<$Res> {
  _$ReplaceAccountSecretCopyWithImpl(this._self, this._then);

  final ReplaceAccountSecret _self;
  final $Res Function(ReplaceAccountSecret) _then;

/// Create a copy of AccountSecretUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(ReplaceAccountSecret(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ClearAccountSecret implements AccountSecretUpdate {
  const ClearAccountSecret();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ClearAccountSecret);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc
mixin _$AccountEdit {


/// Create a copy of AccountEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountEditCopyWith<AccountEdit> get copyWith => _$AccountEditCopyWithImpl<AccountEdit>(this as AccountEdit, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountEdit;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountEdit&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.create, _this.create) || other.create == _this.create)&&(identical(other.templateId, _this.templateId) || other.templateId == _this.templateId)&&(identical(other.protocol, _this.protocol) || other.protocol == _this.protocol)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.baseUrl, _this.baseUrl) || other.baseUrl == _this.baseUrl)&&(identical(other.secret, _this.secret) || other.secret == _this.secret)&&(identical(other.pricingEnabled, _this.pricingEnabled) || other.pricingEnabled == _this.pricingEnabled)&&(identical(other.rebuildModelConfiguration, _this.rebuildModelConfiguration) || other.rebuildModelConfiguration == _this.rebuildModelConfiguration)&&const DeepCollectionEquality().equals(other.customModels, _this.customModels)&&const DeepCollectionEquality().equals(other.connections, _this.connections)&&const DeepCollectionEquality().equals(other.autoCompactLimits, _this.autoCompactLimits));
}


@override
int get hashCode {
  final _this = this as AccountEdit;
  return Object.hash(runtimeType,_this.accountId,_this.create,_this.templateId,_this.protocol,_this.name,_this.baseUrl,_this.secret,_this.pricingEnabled,_this.rebuildModelConfiguration,const DeepCollectionEquality().hash(_this.customModels),const DeepCollectionEquality().hash(_this.connections),const DeepCollectionEquality().hash(_this.autoCompactLimits));
}



}

/// @nodoc
abstract mixin class $AccountEditCopyWith<$Res>  {
  factory $AccountEditCopyWith(AccountEdit value, $Res Function(AccountEdit) _then) = _$AccountEditCopyWithImpl;
@useResult
$Res call({
 String accountId, bool create, FieldEdit<String?> templateId, FieldEdit<String> protocol, FieldEdit<String> name, FieldEdit<String> baseUrl, AccountSecretUpdate secret, FieldEdit<bool> pricingEnabled, bool rebuildModelConfiguration, List<CustomModelChange> customModels, List<ModelConnectionChange> connections, List<ModelLimitChange> autoCompactLimits
});


$FieldEditCopyWith<String?, $Res> get templateId;$FieldEditCopyWith<String, $Res> get protocol;$FieldEditCopyWith<String, $Res> get name;$FieldEditCopyWith<String, $Res> get baseUrl;$AccountSecretUpdateCopyWith<$Res> get secret;$FieldEditCopyWith<bool, $Res> get pricingEnabled;

}
/// @nodoc
class _$AccountEditCopyWithImpl<$Res>
    implements $AccountEditCopyWith<$Res> {
  _$AccountEditCopyWithImpl(this._self, this._then);

  final AccountEdit _self;
  final $Res Function(AccountEdit) _then;

/// Create a copy of AccountEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? create = null,Object? templateId = null,Object? protocol = null,Object? name = null,Object? baseUrl = null,Object? secret = null,Object? pricingEnabled = null,Object? rebuildModelConfiguration = null,Object? customModels = null,Object? connections = null,Object? autoCompactLimits = null,}) {
  return _then(AccountEdit(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,create: null == create ? _self.create : create // ignore: cast_nullable_to_non_nullable
as bool,templateId: null == templateId ? _self.templateId : templateId // ignore: cast_nullable_to_non_nullable
as FieldEdit<String?>,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as FieldEdit<String>,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as FieldEdit<String>,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as FieldEdit<String>,secret: null == secret ? _self.secret : secret // ignore: cast_nullable_to_non_nullable
as AccountSecretUpdate,pricingEnabled: null == pricingEnabled ? _self.pricingEnabled : pricingEnabled // ignore: cast_nullable_to_non_nullable
as FieldEdit<bool>,rebuildModelConfiguration: null == rebuildModelConfiguration ? _self.rebuildModelConfiguration : rebuildModelConfiguration // ignore: cast_nullable_to_non_nullable
as bool,customModels: null == customModels ? _self.customModels : customModels // ignore: cast_nullable_to_non_nullable
as List<CustomModelChange>,connections: null == connections ? _self.connections : connections // ignore: cast_nullable_to_non_nullable
as List<ModelConnectionChange>,autoCompactLimits: null == autoCompactLimits ? _self.autoCompactLimits : autoCompactLimits // ignore: cast_nullable_to_non_nullable
as List<ModelLimitChange>,
  ));
}
/// Create a copy of AccountEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FieldEditCopyWith<String?, $Res> get templateId {

  return $FieldEditCopyWith<String?, $Res>(_self.templateId, (value) {
    return _then(_self.copyWith(templateId: value));
  });
}/// Create a copy of AccountEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FieldEditCopyWith<String, $Res> get protocol {

  return $FieldEditCopyWith<String, $Res>(_self.protocol, (value) {
    return _then(_self.copyWith(protocol: value));
  });
}/// Create a copy of AccountEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FieldEditCopyWith<String, $Res> get name {

  return $FieldEditCopyWith<String, $Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of AccountEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FieldEditCopyWith<String, $Res> get baseUrl {

  return $FieldEditCopyWith<String, $Res>(_self.baseUrl, (value) {
    return _then(_self.copyWith(baseUrl: value));
  });
}/// Create a copy of AccountEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountSecretUpdateCopyWith<$Res> get secret {

  return $AccountSecretUpdateCopyWith<$Res>(_self.secret, (value) {
    return _then(_self.copyWith(secret: value));
  });
}/// Create a copy of AccountEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FieldEditCopyWith<bool, $Res> get pricingEnabled {

  return $FieldEditCopyWith<bool, $Res>(_self.pricingEnabled, (value) {
    return _then(_self.copyWith(pricingEnabled: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountEdit].
extension AccountEditPatterns on AccountEdit {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$CustomModelChange {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CustomModelChange);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CustomModelChange()';
}


}

/// @nodoc
class $CustomModelChangeCopyWith<$Res>  {
$CustomModelChangeCopyWith(CustomModelChange _, $Res Function(CustomModelChange) __);
}


/// Adds pattern-matching-related methods to [CustomModelChange].
extension CustomModelChangePatterns on CustomModelChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UpsertCustomModel value)?  upsert,TResult Function( RemoveCustomModel value)?  remove,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UpsertCustomModel() when upsert != null:
return upsert(_that);case RemoveCustomModel() when remove != null:
return remove(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UpsertCustomModel value)  upsert,required TResult Function( RemoveCustomModel value)  remove,}){
final _that = this;
switch (_that) {
case UpsertCustomModel():
return upsert(_that);case RemoveCustomModel():
return remove(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UpsertCustomModel value)?  upsert,TResult? Function( RemoveCustomModel value)?  remove,}){
final _that = this;
switch (_that) {
case UpsertCustomModel() when upsert != null:
return upsert(_that);case RemoveCustomModel() when remove != null:
return remove(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String? originalModelId,  AccountModelUpdate value)?  upsert,TResult Function( String modelId)?  remove,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UpsertCustomModel() when upsert != null:
return upsert(_that.originalModelId,_that.value);case RemoveCustomModel() when remove != null:
return remove(_that.modelId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String? originalModelId,  AccountModelUpdate value)  upsert,required TResult Function( String modelId)  remove,}) {final _that = this;
switch (_that) {
case UpsertCustomModel():
return upsert(_that.originalModelId,_that.value);case RemoveCustomModel():
return remove(_that.modelId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String? originalModelId,  AccountModelUpdate value)?  upsert,TResult? Function( String modelId)?  remove,}) {final _that = this;
switch (_that) {
case UpsertCustomModel() when upsert != null:
return upsert(_that.originalModelId,_that.value);case RemoveCustomModel() when remove != null:
return remove(_that.modelId);case _:
  return null;

}
}

}

/// @nodoc


class UpsertCustomModel implements CustomModelChange {
  const UpsertCustomModel({required this.originalModelId, required this.value});


 final  String? originalModelId;
 final  AccountModelUpdate value;

/// Create a copy of CustomModelChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpsertCustomModelCopyWith<UpsertCustomModel> get copyWith => _$UpsertCustomModelCopyWithImpl<UpsertCustomModel>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpsertCustomModel&&(identical(other.originalModelId, originalModelId) || other.originalModelId == originalModelId)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,originalModelId,value);
}

@override
String toString() {
    return 'CustomModelChange.upsert(originalModelId: $originalModelId, value: $value)';
}


}

/// @nodoc
abstract mixin class $UpsertCustomModelCopyWith<$Res> implements $CustomModelChangeCopyWith<$Res> {
  factory $UpsertCustomModelCopyWith(UpsertCustomModel value, $Res Function(UpsertCustomModel) _then) = _$UpsertCustomModelCopyWithImpl;
@useResult
$Res call({
 String? originalModelId, AccountModelUpdate value
});


$AccountModelUpdateCopyWith<$Res> get value;

}
/// @nodoc
class _$UpsertCustomModelCopyWithImpl<$Res>
    implements $UpsertCustomModelCopyWith<$Res> {
  _$UpsertCustomModelCopyWithImpl(this._self, this._then);

  final UpsertCustomModel _self;
  final $Res Function(UpsertCustomModel) _then;

/// Create a copy of CustomModelChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? originalModelId = freezed,Object? value = null,}) {
  return _then(UpsertCustomModel(
originalModelId: freezed == originalModelId ? _self.originalModelId : originalModelId // ignore: cast_nullable_to_non_nullable
as String?,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AccountModelUpdate,
  ));
}

/// Create a copy of CustomModelChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelUpdateCopyWith<$Res> get value {

  return $AccountModelUpdateCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class RemoveCustomModel implements CustomModelChange {
  const RemoveCustomModel({required this.modelId});


 final  String modelId;

/// Create a copy of CustomModelChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoveCustomModelCopyWith<RemoveCustomModel> get copyWith => _$RemoveCustomModelCopyWithImpl<RemoveCustomModel>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveCustomModel&&(identical(other.modelId, modelId) || other.modelId == modelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelId);
}

@override
String toString() {
    return 'CustomModelChange.remove(modelId: $modelId)';
}


}

/// @nodoc
abstract mixin class $RemoveCustomModelCopyWith<$Res> implements $CustomModelChangeCopyWith<$Res> {
  factory $RemoveCustomModelCopyWith(RemoveCustomModel value, $Res Function(RemoveCustomModel) _then) = _$RemoveCustomModelCopyWithImpl;
@useResult
$Res call({
 String modelId
});




}
/// @nodoc
class _$RemoveCustomModelCopyWithImpl<$Res>
    implements $RemoveCustomModelCopyWith<$Res> {
  _$RemoveCustomModelCopyWithImpl(this._self, this._then);

  final RemoveCustomModel _self;
  final $Res Function(RemoveCustomModel) _then;

/// Create a copy of CustomModelChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? modelId = null,}) {
  return _then(RemoveCustomModel(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AccountModelUpdate {

 String get modelId; String get displayName; String get wireApi; int? get contextWindow; int? get maxOutputTokens;
/// Create a copy of AccountModelUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelUpdateCopyWith<AccountModelUpdate> get copyWith => _$AccountModelUpdateCopyWithImpl<AccountModelUpdate>(this as AccountModelUpdate, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelUpdate;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelUpdate&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.wireApi, _this.wireApi) || other.wireApi == _this.wireApi)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.maxOutputTokens, _this.maxOutputTokens) || other.maxOutputTokens == _this.maxOutputTokens));
}


@override
int get hashCode {
  final _this = this as AccountModelUpdate;
  return Object.hash(runtimeType,_this.modelId,_this.displayName,_this.wireApi,_this.contextWindow,_this.maxOutputTokens);
}

@override
String toString() {
  final _this = this as AccountModelUpdate;
  return 'AccountModelUpdate(modelId: ${_this.modelId}, displayName: ${_this.displayName}, wireApi: ${_this.wireApi}, contextWindow: ${_this.contextWindow}, maxOutputTokens: ${_this.maxOutputTokens})';
}


}

/// @nodoc
abstract mixin class $AccountModelUpdateCopyWith<$Res>  {
  factory $AccountModelUpdateCopyWith(AccountModelUpdate value, $Res Function(AccountModelUpdate) _then) = _$AccountModelUpdateCopyWithImpl;
@useResult
$Res call({
 String modelId, String displayName, String wireApi, int? contextWindow, int? maxOutputTokens
});




}
/// @nodoc
class _$AccountModelUpdateCopyWithImpl<$Res>
    implements $AccountModelUpdateCopyWith<$Res> {
  _$AccountModelUpdateCopyWithImpl(this._self, this._then);

  final AccountModelUpdate _self;
  final $Res Function(AccountModelUpdate) _then;

/// Create a copy of AccountModelUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelId = null,Object? displayName = null,Object? wireApi = null,Object? contextWindow = freezed,Object? maxOutputTokens = freezed,}) {
  return _then(AccountModelUpdate(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,wireApi: null == wireApi ? _self.wireApi : wireApi // ignore: cast_nullable_to_non_nullable
as String,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxOutputTokens: freezed == maxOutputTokens ? _self.maxOutputTokens : maxOutputTokens // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountModelUpdate].
extension AccountModelUpdatePatterns on AccountModelUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelUpdate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelUpdate() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelUpdate value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelUpdate():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelUpdate value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelUpdate() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String modelId,  String displayName,  String wireApi,  int? contextWindow,  int? maxOutputTokens)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelUpdate() when $default != null:
return $default(_that.modelId,_that.displayName,_that.wireApi,_that.contextWindow,_that.maxOutputTokens);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String modelId,  String displayName,  String wireApi,  int? contextWindow,  int? maxOutputTokens)  $default,) {final _that = this;
switch (_that) {
case _AccountModelUpdate():
return $default(_that.modelId,_that.displayName,_that.wireApi,_that.contextWindow,_that.maxOutputTokens);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String modelId,  String displayName,  String wireApi,  int? contextWindow,  int? maxOutputTokens)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelUpdate() when $default != null:
return $default(_that.modelId,_that.displayName,_that.wireApi,_that.contextWindow,_that.maxOutputTokens);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelUpdate implements AccountModelUpdate {
  const _AccountModelUpdate({required this.modelId, required this.displayName, required this.wireApi, required this.contextWindow, required this.maxOutputTokens});


@override final  String modelId;
@override final  String displayName;
@override final  String wireApi;
@override final  int? contextWindow;
@override final  int? maxOutputTokens;

/// Create a copy of AccountModelUpdate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelUpdateCopyWith<_AccountModelUpdate> get copyWith => __$AccountModelUpdateCopyWithImpl<_AccountModelUpdate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelUpdate&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.wireApi, wireApi) || other.wireApi == wireApi)&&(identical(other.contextWindow, contextWindow) || other.contextWindow == contextWindow)&&(identical(other.maxOutputTokens, maxOutputTokens) || other.maxOutputTokens == maxOutputTokens));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelId,displayName,wireApi,contextWindow,maxOutputTokens);
}

@override
String toString() {
    return 'AccountModelUpdate(modelId: $modelId, displayName: $displayName, wireApi: $wireApi, contextWindow: $contextWindow, maxOutputTokens: $maxOutputTokens)';
}


}

/// @nodoc
abstract mixin class _$AccountModelUpdateCopyWith<$Res> implements $AccountModelUpdateCopyWith<$Res> {
  factory _$AccountModelUpdateCopyWith(_AccountModelUpdate value, $Res Function(_AccountModelUpdate) _then) = __$AccountModelUpdateCopyWithImpl;
@override @useResult
$Res call({
 String modelId, String displayName, String wireApi, int? contextWindow, int? maxOutputTokens
});




}
/// @nodoc
class __$AccountModelUpdateCopyWithImpl<$Res>
    implements _$AccountModelUpdateCopyWith<$Res> {
  __$AccountModelUpdateCopyWithImpl(this._self, this._then);

  final _AccountModelUpdate _self;
  final $Res Function(_AccountModelUpdate) _then;

/// Create a copy of AccountModelUpdate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelId = null,Object? displayName = null,Object? wireApi = null,Object? contextWindow = freezed,Object? maxOutputTokens = freezed,}) {
  return _then(_AccountModelUpdate(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,wireApi: null == wireApi ? _self.wireApi : wireApi // ignore: cast_nullable_to_non_nullable
as String,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxOutputTokens: freezed == maxOutputTokens ? _self.maxOutputTokens : maxOutputTokens // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$ModelConnectionChange {

 String get modelId; String get connectionMode;
/// Create a copy of ModelConnectionChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelConnectionChangeCopyWith<ModelConnectionChange> get copyWith => _$ModelConnectionChangeCopyWithImpl<ModelConnectionChange>(this as ModelConnectionChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelConnectionChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelConnectionChange&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.connectionMode, _this.connectionMode) || other.connectionMode == _this.connectionMode));
}


@override
int get hashCode {
  final _this = this as ModelConnectionChange;
  return Object.hash(runtimeType,_this.modelId,_this.connectionMode);
}

@override
String toString() {
  final _this = this as ModelConnectionChange;
  return 'ModelConnectionChange(modelId: ${_this.modelId}, connectionMode: ${_this.connectionMode})';
}


}

/// @nodoc
abstract mixin class $ModelConnectionChangeCopyWith<$Res>  {
  factory $ModelConnectionChangeCopyWith(ModelConnectionChange value, $Res Function(ModelConnectionChange) _then) = _$ModelConnectionChangeCopyWithImpl;
@useResult
$Res call({
 String modelId, String connectionMode
});




}
/// @nodoc
class _$ModelConnectionChangeCopyWithImpl<$Res>
    implements $ModelConnectionChangeCopyWith<$Res> {
  _$ModelConnectionChangeCopyWithImpl(this._self, this._then);

  final ModelConnectionChange _self;
  final $Res Function(ModelConnectionChange) _then;

/// Create a copy of ModelConnectionChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelId = null,Object? connectionMode = null,}) {
  return _then(ModelConnectionChange(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,connectionMode: null == connectionMode ? _self.connectionMode : connectionMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelConnectionChange].
extension ModelConnectionChangePatterns on ModelConnectionChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelConnectionChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelConnectionChange() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelConnectionChange value)  $default,){
final _that = this;
switch (_that) {
case _ModelConnectionChange():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelConnectionChange value)?  $default,){
final _that = this;
switch (_that) {
case _ModelConnectionChange() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String modelId,  String connectionMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelConnectionChange() when $default != null:
return $default(_that.modelId,_that.connectionMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String modelId,  String connectionMode)  $default,) {final _that = this;
switch (_that) {
case _ModelConnectionChange():
return $default(_that.modelId,_that.connectionMode);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String modelId,  String connectionMode)?  $default,) {final _that = this;
switch (_that) {
case _ModelConnectionChange() when $default != null:
return $default(_that.modelId,_that.connectionMode);case _:
  return null;

}
}

}

/// @nodoc


class _ModelConnectionChange implements ModelConnectionChange {
  const _ModelConnectionChange({required this.modelId, required this.connectionMode});


@override final  String modelId;
@override final  String connectionMode;

/// Create a copy of ModelConnectionChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelConnectionChangeCopyWith<_ModelConnectionChange> get copyWith => __$ModelConnectionChangeCopyWithImpl<_ModelConnectionChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelConnectionChange&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.connectionMode, connectionMode) || other.connectionMode == connectionMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelId,connectionMode);
}

@override
String toString() {
    return 'ModelConnectionChange(modelId: $modelId, connectionMode: $connectionMode)';
}


}

/// @nodoc
abstract mixin class _$ModelConnectionChangeCopyWith<$Res> implements $ModelConnectionChangeCopyWith<$Res> {
  factory _$ModelConnectionChangeCopyWith(_ModelConnectionChange value, $Res Function(_ModelConnectionChange) _then) = __$ModelConnectionChangeCopyWithImpl;
@override @useResult
$Res call({
 String modelId, String connectionMode
});




}
/// @nodoc
class __$ModelConnectionChangeCopyWithImpl<$Res>
    implements _$ModelConnectionChangeCopyWith<$Res> {
  __$ModelConnectionChangeCopyWithImpl(this._self, this._then);

  final _ModelConnectionChange _self;
  final $Res Function(_ModelConnectionChange) _then;

/// Create a copy of ModelConnectionChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelId = null,Object? connectionMode = null,}) {
  return _then(_ModelConnectionChange(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,connectionMode: null == connectionMode ? _self.connectionMode : connectionMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ModelLimitChange {

 String get modelId; int? get overrideLimit;
/// Create a copy of ModelLimitChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelLimitChangeCopyWith<ModelLimitChange> get copyWith => _$ModelLimitChangeCopyWithImpl<ModelLimitChange>(this as ModelLimitChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelLimitChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelLimitChange&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.overrideLimit, _this.overrideLimit) || other.overrideLimit == _this.overrideLimit));
}


@override
int get hashCode {
  final _this = this as ModelLimitChange;
  return Object.hash(runtimeType,_this.modelId,_this.overrideLimit);
}

@override
String toString() {
  final _this = this as ModelLimitChange;
  return 'ModelLimitChange(modelId: ${_this.modelId}, overrideLimit: ${_this.overrideLimit})';
}


}

/// @nodoc
abstract mixin class $ModelLimitChangeCopyWith<$Res>  {
  factory $ModelLimitChangeCopyWith(ModelLimitChange value, $Res Function(ModelLimitChange) _then) = _$ModelLimitChangeCopyWithImpl;
@useResult
$Res call({
 String modelId, int? overrideLimit
});




}
/// @nodoc
class _$ModelLimitChangeCopyWithImpl<$Res>
    implements $ModelLimitChangeCopyWith<$Res> {
  _$ModelLimitChangeCopyWithImpl(this._self, this._then);

  final ModelLimitChange _self;
  final $Res Function(ModelLimitChange) _then;

/// Create a copy of ModelLimitChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelId = null,Object? overrideLimit = freezed,}) {
  return _then(ModelLimitChange(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,overrideLimit: freezed == overrideLimit ? _self.overrideLimit : overrideLimit // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelLimitChange].
extension ModelLimitChangePatterns on ModelLimitChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelLimitChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelLimitChange() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelLimitChange value)  $default,){
final _that = this;
switch (_that) {
case _ModelLimitChange():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelLimitChange value)?  $default,){
final _that = this;
switch (_that) {
case _ModelLimitChange() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String modelId,  int? overrideLimit)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelLimitChange() when $default != null:
return $default(_that.modelId,_that.overrideLimit);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String modelId,  int? overrideLimit)  $default,) {final _that = this;
switch (_that) {
case _ModelLimitChange():
return $default(_that.modelId,_that.overrideLimit);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String modelId,  int? overrideLimit)?  $default,) {final _that = this;
switch (_that) {
case _ModelLimitChange() when $default != null:
return $default(_that.modelId,_that.overrideLimit);case _:
  return null;

}
}

}

/// @nodoc


class _ModelLimitChange implements ModelLimitChange {
  const _ModelLimitChange({required this.modelId, required this.overrideLimit});


@override final  String modelId;
@override final  int? overrideLimit;

/// Create a copy of ModelLimitChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelLimitChangeCopyWith<_ModelLimitChange> get copyWith => __$ModelLimitChangeCopyWithImpl<_ModelLimitChange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelLimitChange&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.overrideLimit, overrideLimit) || other.overrideLimit == overrideLimit));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelId,overrideLimit);
}

@override
String toString() {
    return 'ModelLimitChange(modelId: $modelId, overrideLimit: $overrideLimit)';
}


}

/// @nodoc
abstract mixin class _$ModelLimitChangeCopyWith<$Res> implements $ModelLimitChangeCopyWith<$Res> {
  factory _$ModelLimitChangeCopyWith(_ModelLimitChange value, $Res Function(_ModelLimitChange) _then) = __$ModelLimitChangeCopyWithImpl;
@override @useResult
$Res call({
 String modelId, int? overrideLimit
});




}
/// @nodoc
class __$ModelLimitChangeCopyWithImpl<$Res>
    implements _$ModelLimitChangeCopyWith<$Res> {
  __$ModelLimitChangeCopyWithImpl(this._self, this._then);

  final _ModelLimitChange _self;
  final $Res Function(_ModelLimitChange) _then;

/// Create a copy of ModelLimitChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelId = null,Object? overrideLimit = freezed,}) {
  return _then(_ModelLimitChange(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,overrideLimit: freezed == overrideLimit ? _self.overrideLimit : overrideLimit // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
