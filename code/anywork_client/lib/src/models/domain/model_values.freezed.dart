// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountModelKey {

 String get accountId; String get modelId;
/// Create a copy of AccountModelKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<AccountModelKey> get copyWith => _$AccountModelKeyCopyWithImpl<AccountModelKey>(this as AccountModelKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelKey&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId));
}


@override
int get hashCode {
  final _this = this as AccountModelKey;
  return Object.hash(runtimeType,_this.accountId,_this.modelId);
}

@override
String toString() {
  final _this = this as AccountModelKey;
  return 'AccountModelKey(accountId: ${_this.accountId}, modelId: ${_this.modelId})';
}


}

/// @nodoc
abstract mixin class $AccountModelKeyCopyWith<$Res>  {
  factory $AccountModelKeyCopyWith(AccountModelKey value, $Res Function(AccountModelKey) _then) = _$AccountModelKeyCopyWithImpl;
@useResult
$Res call({
 String accountId, String modelId
});




}
/// @nodoc
class _$AccountModelKeyCopyWithImpl<$Res>
    implements $AccountModelKeyCopyWith<$Res> {
  _$AccountModelKeyCopyWithImpl(this._self, this._then);

  final AccountModelKey _self;
  final $Res Function(AccountModelKey) _then;

/// Create a copy of AccountModelKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? modelId = null,}) {
  return _then(AccountModelKey(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountModelKey].
extension AccountModelKeyPatterns on AccountModelKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelKey value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelKey value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  String modelId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelKey() when $default != null:
return $default(_that.accountId,_that.modelId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  String modelId)  $default,) {final _that = this;
switch (_that) {
case _AccountModelKey():
return $default(_that.accountId,_that.modelId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  String modelId)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelKey() when $default != null:
return $default(_that.accountId,_that.modelId);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelKey implements AccountModelKey {
  const _AccountModelKey({required this.accountId, required this.modelId});


@override final  String accountId;
@override final  String modelId;

/// Create a copy of AccountModelKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelKeyCopyWith<_AccountModelKey> get copyWith => __$AccountModelKeyCopyWithImpl<_AccountModelKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelKey&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,modelId);
}

@override
String toString() {
    return 'AccountModelKey(accountId: $accountId, modelId: $modelId)';
}


}

/// @nodoc
abstract mixin class _$AccountModelKeyCopyWith<$Res> implements $AccountModelKeyCopyWith<$Res> {
  factory _$AccountModelKeyCopyWith(_AccountModelKey value, $Res Function(_AccountModelKey) _then) = __$AccountModelKeyCopyWithImpl;
@override @useResult
$Res call({
 String accountId, String modelId
});




}
/// @nodoc
class __$AccountModelKeyCopyWithImpl<$Res>
    implements _$AccountModelKeyCopyWith<$Res> {
  __$AccountModelKeyCopyWithImpl(this._self, this._then);

  final _AccountModelKey _self;
  final $Res Function(_AccountModelKey) _then;

/// Create a copy of AccountModelKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? modelId = null,}) {
  return _then(_AccountModelKey(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ModelSelection {

 AccountModelKey get model; String? get effort;
/// Create a copy of ModelSelection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<ModelSelection> get copyWith => _$ModelSelectionCopyWithImpl<ModelSelection>(this as ModelSelection, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelSelection;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelSelection&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as ModelSelection;
  return Object.hash(runtimeType,_this.model,_this.effort);
}

@override
String toString() {
  final _this = this as ModelSelection;
  return 'ModelSelection(model: ${_this.model}, effort: ${_this.effort})';
}


}

/// @nodoc
abstract mixin class $ModelSelectionCopyWith<$Res>  {
  factory $ModelSelectionCopyWith(ModelSelection value, $Res Function(ModelSelection) _then) = _$ModelSelectionCopyWithImpl;
@useResult
$Res call({
 AccountModelKey model, String? effort
});


$AccountModelKeyCopyWith<$Res> get model;

}
/// @nodoc
class _$ModelSelectionCopyWithImpl<$Res>
    implements $ModelSelectionCopyWith<$Res> {
  _$ModelSelectionCopyWithImpl(this._self, this._then);

  final ModelSelection _self;
  final $Res Function(ModelSelection) _then;

/// Create a copy of ModelSelection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? model = null,Object? effort = freezed,}) {
  return _then(ModelSelection(
model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of ModelSelection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get model {

  return $AccountModelKeyCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelSelection].
extension ModelSelectionPatterns on ModelSelection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelSelection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelSelection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelSelection value)  $default,){
final _that = this;
switch (_that) {
case _ModelSelection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelSelection value)?  $default,){
final _that = this;
switch (_that) {
case _ModelSelection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountModelKey model,  String? effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelSelection() when $default != null:
return $default(_that.model,_that.effort);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountModelKey model,  String? effort)  $default,) {final _that = this;
switch (_that) {
case _ModelSelection():
return $default(_that.model,_that.effort);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountModelKey model,  String? effort)?  $default,) {final _that = this;
switch (_that) {
case _ModelSelection() when $default != null:
return $default(_that.model,_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _ModelSelection implements ModelSelection {
  const _ModelSelection({required this.model, required this.effort});


@override final  AccountModelKey model;
@override final  String? effort;

/// Create a copy of ModelSelection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelSelectionCopyWith<_ModelSelection> get copyWith => __$ModelSelectionCopyWithImpl<_ModelSelection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelSelection&&(identical(other.model, model) || other.model == model)&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,model,effort);
}

@override
String toString() {
    return 'ModelSelection(model: $model, effort: $effort)';
}


}

/// @nodoc
abstract mixin class _$ModelSelectionCopyWith<$Res> implements $ModelSelectionCopyWith<$Res> {
  factory _$ModelSelectionCopyWith(_ModelSelection value, $Res Function(_ModelSelection) _then) = __$ModelSelectionCopyWithImpl;
@override @useResult
$Res call({
 AccountModelKey model, String? effort
});


@override $AccountModelKeyCopyWith<$Res> get model;

}
/// @nodoc
class __$ModelSelectionCopyWithImpl<$Res>
    implements _$ModelSelectionCopyWith<$Res> {
  __$ModelSelectionCopyWithImpl(this._self, this._then);

  final _ModelSelection _self;
  final $Res Function(_ModelSelection) _then;

/// Create a copy of ModelSelection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? model = null,Object? effort = freezed,}) {
  return _then(_ModelSelection(
model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of ModelSelection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get model {

  return $AccountModelKeyCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}
}

/// @nodoc
mixin _$ModelDescriptor {


/// Create a copy of ModelDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelDescriptorCopyWith<ModelDescriptor> get copyWith => _$ModelDescriptorCopyWithImpl<ModelDescriptor>(this as ModelDescriptor, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelDescriptor;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelDescriptor&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&const DeepCollectionEquality().equals(other.typeSupport, _this.typeSupport)&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.maxContextWindow, _this.maxContextWindow) || other.maxContextWindow == _this.maxContextWindow)&&(identical(other.context, _this.context) || other.context == _this.context)&&(identical(other.maxOutputTokens, _this.maxOutputTokens) || other.maxOutputTokens == _this.maxOutputTokens)&&(identical(other.transport, _this.transport) || other.transport == _this.transport)&&(identical(other.capabilities, _this.capabilities) || other.capabilities == _this.capabilities)&&(identical(other.reasoning, _this.reasoning) || other.reasoning == _this.reasoning)&&(identical(other.pricing, _this.pricing) || other.pricing == _this.pricing));
}


@override
int get hashCode {
  final _this = this as ModelDescriptor;
  return Object.hash(runtimeType,_this.modelId,_this.enabled,const DeepCollectionEquality().hash(_this.typeSupport),_this.origin,_this.displayName,_this.description,_this.contextWindow,_this.maxContextWindow,_this.context,_this.maxOutputTokens,_this.transport,_this.capabilities,_this.reasoning,_this.pricing);
}

@override
String toString() {
  final _this = this as ModelDescriptor;
  return 'ModelDescriptor(modelId: ${_this.modelId}, enabled: ${_this.enabled}, typeSupport: ${_this.typeSupport}, origin: ${_this.origin}, displayName: ${_this.displayName}, description: ${_this.description}, contextWindow: ${_this.contextWindow}, maxContextWindow: ${_this.maxContextWindow}, context: ${_this.context}, maxOutputTokens: ${_this.maxOutputTokens}, transport: ${_this.transport}, capabilities: ${_this.capabilities}, reasoning: ${_this.reasoning}, pricing: ${_this.pricing})';
}


}

/// @nodoc
abstract mixin class $ModelDescriptorCopyWith<$Res>  {
  factory $ModelDescriptorCopyWith(ModelDescriptor value, $Res Function(ModelDescriptor) _then) = _$ModelDescriptorCopyWithImpl;
@useResult
$Res call({
 String modelId, bool enabled, List<ModelTypeSupport> typeSupport, ModelOrigin origin, String displayName, String? description, int? contextWindow, int? maxContextWindow, ModelContextResolution context, int? maxOutputTokens, ModelTransportDescriptor transport, ModelCapabilities capabilities, ModelReasoningDescriptor? reasoning, ModelPricing? pricing
});


$ModelContextResolutionCopyWith<$Res> get context;$ModelTransportDescriptorCopyWith<$Res> get transport;$ModelCapabilitiesCopyWith<$Res> get capabilities;$ModelReasoningDescriptorCopyWith<$Res>? get reasoning;$ModelPricingCopyWith<$Res>? get pricing;

}
/// @nodoc
class _$ModelDescriptorCopyWithImpl<$Res>
    implements $ModelDescriptorCopyWith<$Res> {
  _$ModelDescriptorCopyWithImpl(this._self, this._then);

  final ModelDescriptor _self;
  final $Res Function(ModelDescriptor) _then;

/// Create a copy of ModelDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelId = null,Object? enabled = null,Object? typeSupport = null,Object? origin = null,Object? displayName = null,Object? description = freezed,Object? contextWindow = freezed,Object? maxContextWindow = freezed,Object? context = null,Object? maxOutputTokens = freezed,Object? transport = null,Object? capabilities = null,Object? reasoning = freezed,Object? pricing = freezed,}) {
  return _then(ModelDescriptor(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,typeSupport: null == typeSupport ? _self.typeSupport : typeSupport // ignore: cast_nullable_to_non_nullable
as List<ModelTypeSupport>,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ModelOrigin,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxContextWindow: freezed == maxContextWindow ? _self.maxContextWindow : maxContextWindow // ignore: cast_nullable_to_non_nullable
as int?,context: null == context ? _self.context : context // ignore: cast_nullable_to_non_nullable
as ModelContextResolution,maxOutputTokens: freezed == maxOutputTokens ? _self.maxOutputTokens : maxOutputTokens // ignore: cast_nullable_to_non_nullable
as int?,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as ModelTransportDescriptor,capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as ModelCapabilities,reasoning: freezed == reasoning ? _self.reasoning : reasoning // ignore: cast_nullable_to_non_nullable
as ModelReasoningDescriptor?,pricing: freezed == pricing ? _self.pricing : pricing // ignore: cast_nullable_to_non_nullable
as ModelPricing?,
  ));
}
/// Create a copy of ModelDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelContextResolutionCopyWith<$Res> get context {

  return $ModelContextResolutionCopyWith<$Res>(_self.context, (value) {
    return _then(_self.copyWith(context: value));
  });
}/// Create a copy of ModelDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelTransportDescriptorCopyWith<$Res> get transport {

  return $ModelTransportDescriptorCopyWith<$Res>(_self.transport, (value) {
    return _then(_self.copyWith(transport: value));
  });
}/// Create a copy of ModelDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCapabilitiesCopyWith<$Res> get capabilities {

  return $ModelCapabilitiesCopyWith<$Res>(_self.capabilities, (value) {
    return _then(_self.copyWith(capabilities: value));
  });
}/// Create a copy of ModelDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelReasoningDescriptorCopyWith<$Res>? get reasoning {
    if (_self.reasoning == null) {
    return null;
  }

  return $ModelReasoningDescriptorCopyWith<$Res>(_self.reasoning!, (value) {
    return _then(_self.copyWith(reasoning: value));
  });
}/// Create a copy of ModelDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelPricingCopyWith<$Res>? get pricing {
    if (_self.pricing == null) {
    return null;
  }

  return $ModelPricingCopyWith<$Res>(_self.pricing!, (value) {
    return _then(_self.copyWith(pricing: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelDescriptor].
extension ModelDescriptorPatterns on ModelDescriptor {
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
mixin _$ModelTypeSupport {


/// Create a copy of ModelTypeSupport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelTypeSupportCopyWith<ModelTypeSupport> get copyWith => _$ModelTypeSupportCopyWithImpl<ModelTypeSupport>(this as ModelTypeSupport, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelTypeSupport;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelTypeSupport&&(identical(other.modelType, _this.modelType) || other.modelType == _this.modelType)&&const DeepCollectionEquality().equals(other.exclusions, _this.exclusions));
}


@override
int get hashCode {
  final _this = this as ModelTypeSupport;
  return Object.hash(runtimeType,_this.modelType,const DeepCollectionEquality().hash(_this.exclusions));
}

@override
String toString() {
  final _this = this as ModelTypeSupport;
  return 'ModelTypeSupport(modelType: ${_this.modelType}, exclusions: ${_this.exclusions})';
}


}

/// @nodoc
abstract mixin class $ModelTypeSupportCopyWith<$Res>  {
  factory $ModelTypeSupportCopyWith(ModelTypeSupport value, $Res Function(ModelTypeSupport) _then) = _$ModelTypeSupportCopyWithImpl;
@useResult
$Res call({
 ModelType modelType, List<ModelTypeExclusion> exclusions
});




}
/// @nodoc
class _$ModelTypeSupportCopyWithImpl<$Res>
    implements $ModelTypeSupportCopyWith<$Res> {
  _$ModelTypeSupportCopyWithImpl(this._self, this._then);

  final ModelTypeSupport _self;
  final $Res Function(ModelTypeSupport) _then;

/// Create a copy of ModelTypeSupport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelType = null,Object? exclusions = null,}) {
  return _then(ModelTypeSupport(
modelType: null == modelType ? _self.modelType : modelType // ignore: cast_nullable_to_non_nullable
as ModelType,exclusions: null == exclusions ? _self.exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<ModelTypeExclusion>,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelTypeSupport].
extension ModelTypeSupportPatterns on ModelTypeSupport {
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
mixin _$ModelContextResolution {

 ModelContextUnavailable? get unavailable; int? get contextWindow; int? get inputTokenLimit; int? get autoCompactLimit; ModelContextAdjustment? get adjustment;
/// Create a copy of ModelContextResolution
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelContextResolutionCopyWith<ModelContextResolution> get copyWith => _$ModelContextResolutionCopyWithImpl<ModelContextResolution>(this as ModelContextResolution, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelContextResolution;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelContextResolution&&(identical(other.unavailable, _this.unavailable) || other.unavailable == _this.unavailable)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.inputTokenLimit, _this.inputTokenLimit) || other.inputTokenLimit == _this.inputTokenLimit)&&(identical(other.autoCompactLimit, _this.autoCompactLimit) || other.autoCompactLimit == _this.autoCompactLimit)&&(identical(other.adjustment, _this.adjustment) || other.adjustment == _this.adjustment));
}


@override
int get hashCode {
  final _this = this as ModelContextResolution;
  return Object.hash(runtimeType,_this.unavailable,_this.contextWindow,_this.inputTokenLimit,_this.autoCompactLimit,_this.adjustment);
}

@override
String toString() {
  final _this = this as ModelContextResolution;
  return 'ModelContextResolution(unavailable: ${_this.unavailable}, contextWindow: ${_this.contextWindow}, inputTokenLimit: ${_this.inputTokenLimit}, autoCompactLimit: ${_this.autoCompactLimit}, adjustment: ${_this.adjustment})';
}


}

/// @nodoc
abstract mixin class $ModelContextResolutionCopyWith<$Res>  {
  factory $ModelContextResolutionCopyWith(ModelContextResolution value, $Res Function(ModelContextResolution) _then) = _$ModelContextResolutionCopyWithImpl;
@useResult
$Res call({
 ModelContextUnavailable? unavailable, int? contextWindow, int? inputTokenLimit, int? autoCompactLimit, ModelContextAdjustment? adjustment
});




}
/// @nodoc
class _$ModelContextResolutionCopyWithImpl<$Res>
    implements $ModelContextResolutionCopyWith<$Res> {
  _$ModelContextResolutionCopyWithImpl(this._self, this._then);

  final ModelContextResolution _self;
  final $Res Function(ModelContextResolution) _then;

/// Create a copy of ModelContextResolution
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? unavailable = freezed,Object? contextWindow = freezed,Object? inputTokenLimit = freezed,Object? autoCompactLimit = freezed,Object? adjustment = freezed,}) {
  return _then(ModelContextResolution(
unavailable: freezed == unavailable ? _self.unavailable : unavailable // ignore: cast_nullable_to_non_nullable
as ModelContextUnavailable?,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,inputTokenLimit: freezed == inputTokenLimit ? _self.inputTokenLimit : inputTokenLimit // ignore: cast_nullable_to_non_nullable
as int?,autoCompactLimit: freezed == autoCompactLimit ? _self.autoCompactLimit : autoCompactLimit // ignore: cast_nullable_to_non_nullable
as int?,adjustment: freezed == adjustment ? _self.adjustment : adjustment // ignore: cast_nullable_to_non_nullable
as ModelContextAdjustment?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelContextResolution].
extension ModelContextResolutionPatterns on ModelContextResolution {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelContextResolution value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelContextResolution() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelContextResolution value)  $default,){
final _that = this;
switch (_that) {
case _ModelContextResolution():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelContextResolution value)?  $default,){
final _that = this;
switch (_that) {
case _ModelContextResolution() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModelContextUnavailable? unavailable,  int? contextWindow,  int? inputTokenLimit,  int? autoCompactLimit,  ModelContextAdjustment? adjustment)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelContextResolution() when $default != null:
return $default(_that.unavailable,_that.contextWindow,_that.inputTokenLimit,_that.autoCompactLimit,_that.adjustment);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModelContextUnavailable? unavailable,  int? contextWindow,  int? inputTokenLimit,  int? autoCompactLimit,  ModelContextAdjustment? adjustment)  $default,) {final _that = this;
switch (_that) {
case _ModelContextResolution():
return $default(_that.unavailable,_that.contextWindow,_that.inputTokenLimit,_that.autoCompactLimit,_that.adjustment);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModelContextUnavailable? unavailable,  int? contextWindow,  int? inputTokenLimit,  int? autoCompactLimit,  ModelContextAdjustment? adjustment)?  $default,) {final _that = this;
switch (_that) {
case _ModelContextResolution() when $default != null:
return $default(_that.unavailable,_that.contextWindow,_that.inputTokenLimit,_that.autoCompactLimit,_that.adjustment);case _:
  return null;

}
}

}

/// @nodoc


class _ModelContextResolution implements ModelContextResolution {
  const _ModelContextResolution({required this.unavailable, required this.contextWindow, required this.inputTokenLimit, required this.autoCompactLimit, required this.adjustment});


@override final  ModelContextUnavailable? unavailable;
@override final  int? contextWindow;
@override final  int? inputTokenLimit;
@override final  int? autoCompactLimit;
@override final  ModelContextAdjustment? adjustment;

/// Create a copy of ModelContextResolution
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelContextResolutionCopyWith<_ModelContextResolution> get copyWith => __$ModelContextResolutionCopyWithImpl<_ModelContextResolution>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelContextResolution&&(identical(other.unavailable, unavailable) || other.unavailable == unavailable)&&(identical(other.contextWindow, contextWindow) || other.contextWindow == contextWindow)&&(identical(other.inputTokenLimit, inputTokenLimit) || other.inputTokenLimit == inputTokenLimit)&&(identical(other.autoCompactLimit, autoCompactLimit) || other.autoCompactLimit == autoCompactLimit)&&(identical(other.adjustment, adjustment) || other.adjustment == adjustment));
}


@override
int get hashCode {
    return Object.hash(runtimeType,unavailable,contextWindow,inputTokenLimit,autoCompactLimit,adjustment);
}

@override
String toString() {
    return 'ModelContextResolution(unavailable: $unavailable, contextWindow: $contextWindow, inputTokenLimit: $inputTokenLimit, autoCompactLimit: $autoCompactLimit, adjustment: $adjustment)';
}


}

/// @nodoc
abstract mixin class _$ModelContextResolutionCopyWith<$Res> implements $ModelContextResolutionCopyWith<$Res> {
  factory _$ModelContextResolutionCopyWith(_ModelContextResolution value, $Res Function(_ModelContextResolution) _then) = __$ModelContextResolutionCopyWithImpl;
@override @useResult
$Res call({
 ModelContextUnavailable? unavailable, int? contextWindow, int? inputTokenLimit, int? autoCompactLimit, ModelContextAdjustment? adjustment
});




}
/// @nodoc
class __$ModelContextResolutionCopyWithImpl<$Res>
    implements _$ModelContextResolutionCopyWith<$Res> {
  __$ModelContextResolutionCopyWithImpl(this._self, this._then);

  final _ModelContextResolution _self;
  final $Res Function(_ModelContextResolution) _then;

/// Create a copy of ModelContextResolution
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? unavailable = freezed,Object? contextWindow = freezed,Object? inputTokenLimit = freezed,Object? autoCompactLimit = freezed,Object? adjustment = freezed,}) {
  return _then(_ModelContextResolution(
unavailable: freezed == unavailable ? _self.unavailable : unavailable // ignore: cast_nullable_to_non_nullable
as ModelContextUnavailable?,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,inputTokenLimit: freezed == inputTokenLimit ? _self.inputTokenLimit : inputTokenLimit // ignore: cast_nullable_to_non_nullable
as int?,autoCompactLimit: freezed == autoCompactLimit ? _self.autoCompactLimit : autoCompactLimit // ignore: cast_nullable_to_non_nullable
as int?,adjustment: freezed == adjustment ? _self.adjustment : adjustment // ignore: cast_nullable_to_non_nullable
as ModelContextAdjustment?,
  ));
}


}

/// @nodoc
mixin _$ModelTransportDescriptor {


/// Create a copy of ModelTransportDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelTransportDescriptorCopyWith<ModelTransportDescriptor> get copyWith => _$ModelTransportDescriptorCopyWithImpl<ModelTransportDescriptor>(this as ModelTransportDescriptor, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelTransportDescriptor;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelTransportDescriptor&&(identical(other.protocol, _this.protocol) || other.protocol == _this.protocol)&&const DeepCollectionEquality().equals(other.connectionModes, _this.connectionModes)&&(identical(other.defaultConnectionMode, _this.defaultConnectionMode) || other.defaultConnectionMode == _this.defaultConnectionMode));
}


@override
int get hashCode {
  final _this = this as ModelTransportDescriptor;
  return Object.hash(runtimeType,_this.protocol,const DeepCollectionEquality().hash(_this.connectionModes),_this.defaultConnectionMode);
}

@override
String toString() {
  final _this = this as ModelTransportDescriptor;
  return 'ModelTransportDescriptor(protocol: ${_this.protocol}, connectionModes: ${_this.connectionModes}, defaultConnectionMode: ${_this.defaultConnectionMode})';
}


}

/// @nodoc
abstract mixin class $ModelTransportDescriptorCopyWith<$Res>  {
  factory $ModelTransportDescriptorCopyWith(ModelTransportDescriptor value, $Res Function(ModelTransportDescriptor) _then) = _$ModelTransportDescriptorCopyWithImpl;
@useResult
$Res call({
 String protocol, List<ConnectionMode> connectionModes, String defaultConnectionMode
});




}
/// @nodoc
class _$ModelTransportDescriptorCopyWithImpl<$Res>
    implements $ModelTransportDescriptorCopyWith<$Res> {
  _$ModelTransportDescriptorCopyWithImpl(this._self, this._then);

  final ModelTransportDescriptor _self;
  final $Res Function(ModelTransportDescriptor) _then;

/// Create a copy of ModelTransportDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? protocol = null,Object? connectionModes = null,Object? defaultConnectionMode = null,}) {
  return _then(ModelTransportDescriptor(
protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as String,connectionModes: null == connectionModes ? _self.connectionModes : connectionModes // ignore: cast_nullable_to_non_nullable
as List<ConnectionMode>,defaultConnectionMode: null == defaultConnectionMode ? _self.defaultConnectionMode : defaultConnectionMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelTransportDescriptor].
extension ModelTransportDescriptorPatterns on ModelTransportDescriptor {
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
mixin _$ConnectionMode {

 String get id; String get displayName;
/// Create a copy of ConnectionMode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionModeCopyWith<ConnectionMode> get copyWith => _$ConnectionModeCopyWithImpl<ConnectionMode>(this as ConnectionMode, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConnectionMode;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionMode&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName));
}


@override
int get hashCode {
  final _this = this as ConnectionMode;
  return Object.hash(runtimeType,_this.id,_this.displayName);
}

@override
String toString() {
  final _this = this as ConnectionMode;
  return 'ConnectionMode(id: ${_this.id}, displayName: ${_this.displayName})';
}


}

/// @nodoc
abstract mixin class $ConnectionModeCopyWith<$Res>  {
  factory $ConnectionModeCopyWith(ConnectionMode value, $Res Function(ConnectionMode) _then) = _$ConnectionModeCopyWithImpl;
@useResult
$Res call({
 String id, String displayName
});




}
/// @nodoc
class _$ConnectionModeCopyWithImpl<$Res>
    implements $ConnectionModeCopyWith<$Res> {
  _$ConnectionModeCopyWithImpl(this._self, this._then);

  final ConnectionMode _self;
  final $Res Function(ConnectionMode) _then;

/// Create a copy of ConnectionMode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,}) {
  return _then(ConnectionMode(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ConnectionMode].
extension ConnectionModePatterns on ConnectionMode {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConnectionMode value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConnectionMode() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConnectionMode value)  $default,){
final _that = this;
switch (_that) {
case _ConnectionMode():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConnectionMode value)?  $default,){
final _that = this;
switch (_that) {
case _ConnectionMode() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String displayName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConnectionMode() when $default != null:
return $default(_that.id,_that.displayName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String displayName)  $default,) {final _that = this;
switch (_that) {
case _ConnectionMode():
return $default(_that.id,_that.displayName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String displayName)?  $default,) {final _that = this;
switch (_that) {
case _ConnectionMode() when $default != null:
return $default(_that.id,_that.displayName);case _:
  return null;

}
}

}

/// @nodoc


class _ConnectionMode implements ConnectionMode {
  const _ConnectionMode({required this.id, required this.displayName});


@override final  String id;
@override final  String displayName;

/// Create a copy of ConnectionMode
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConnectionModeCopyWith<_ConnectionMode> get copyWith => __$ConnectionModeCopyWithImpl<_ConnectionMode>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConnectionMode&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName);
}

@override
String toString() {
    return 'ConnectionMode(id: $id, displayName: $displayName)';
}


}

/// @nodoc
abstract mixin class _$ConnectionModeCopyWith<$Res> implements $ConnectionModeCopyWith<$Res> {
  factory _$ConnectionModeCopyWith(_ConnectionMode value, $Res Function(_ConnectionMode) _then) = __$ConnectionModeCopyWithImpl;
@override @useResult
$Res call({
 String id, String displayName
});




}
/// @nodoc
class __$ConnectionModeCopyWithImpl<$Res>
    implements _$ConnectionModeCopyWith<$Res> {
  __$ConnectionModeCopyWithImpl(this._self, this._then);

  final _ConnectionMode _self;
  final $Res Function(_ConnectionMode) _then;

/// Create a copy of ConnectionMode
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,}) {
  return _then(_ConnectionMode(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ModelCapabilities {


/// Create a copy of ModelCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCapabilitiesCopyWith<ModelCapabilities> get copyWith => _$ModelCapabilitiesCopyWithImpl<ModelCapabilities>(this as ModelCapabilities, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelCapabilities;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCapabilities&&const DeepCollectionEquality().equals(other.input, _this.input)&&const DeepCollectionEquality().equals(other.output, _this.output)&&(identical(other.streaming, _this.streaming) || other.streaming == _this.streaming)&&(identical(other.temperature, _this.temperature) || other.temperature == _this.temperature)&&(identical(other.reasoning, _this.reasoning) || other.reasoning == _this.reasoning)&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.functionCalling, _this.functionCalling) || other.functionCalling == _this.functionCalling)&&(identical(other.parallelToolCalls, _this.parallelToolCalls) || other.parallelToolCalls == _this.parallelToolCalls)&&(identical(other.customTools, _this.customTools) || other.customTools == _this.customTools)&&(identical(other.freeformTools, _this.freeformTools) || other.freeformTools == _this.freeformTools)&&(identical(other.instructionSnapshotOverrides, _this.instructionSnapshotOverrides) || other.instructionSnapshotOverrides == _this.instructionSnapshotOverrides)&&(identical(other.nativeContextFamily, _this.nativeContextFamily) || other.nativeContextFamily == _this.nativeContextFamily));
}


@override
int get hashCode {
  final _this = this as ModelCapabilities;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.input),const DeepCollectionEquality().hash(_this.output),_this.streaming,_this.temperature,_this.reasoning,_this.webSearch,_this.functionCalling,_this.parallelToolCalls,_this.customTools,_this.freeformTools,_this.instructionSnapshotOverrides,_this.nativeContextFamily);
}

@override
String toString() {
  final _this = this as ModelCapabilities;
  return 'ModelCapabilities(input: ${_this.input}, output: ${_this.output}, streaming: ${_this.streaming}, temperature: ${_this.temperature}, reasoning: ${_this.reasoning}, webSearch: ${_this.webSearch}, functionCalling: ${_this.functionCalling}, parallelToolCalls: ${_this.parallelToolCalls}, customTools: ${_this.customTools}, freeformTools: ${_this.freeformTools}, instructionSnapshotOverrides: ${_this.instructionSnapshotOverrides}, nativeContextFamily: ${_this.nativeContextFamily})';
}


}

/// @nodoc
abstract mixin class $ModelCapabilitiesCopyWith<$Res>  {
  factory $ModelCapabilitiesCopyWith(ModelCapabilities value, $Res Function(ModelCapabilities) _then) = _$ModelCapabilitiesCopyWithImpl;
@useResult
$Res call({
 List<ModelInputCapability> input, List<ModelModality> output, bool streaming, bool temperature, bool reasoning, bool webSearch, bool functionCalling, bool parallelToolCalls, bool customTools, bool freeformTools, bool instructionSnapshotOverrides, String? nativeContextFamily
});




}
/// @nodoc
class _$ModelCapabilitiesCopyWithImpl<$Res>
    implements $ModelCapabilitiesCopyWith<$Res> {
  _$ModelCapabilitiesCopyWithImpl(this._self, this._then);

  final ModelCapabilities _self;
  final $Res Function(ModelCapabilities) _then;

/// Create a copy of ModelCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? input = null,Object? output = null,Object? streaming = null,Object? temperature = null,Object? reasoning = null,Object? webSearch = null,Object? functionCalling = null,Object? parallelToolCalls = null,Object? customTools = null,Object? freeformTools = null,Object? instructionSnapshotOverrides = null,Object? nativeContextFamily = freezed,}) {
  return _then(ModelCapabilities(
input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as List<ModelInputCapability>,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as List<ModelModality>,streaming: null == streaming ? _self.streaming : streaming // ignore: cast_nullable_to_non_nullable
as bool,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as bool,reasoning: null == reasoning ? _self.reasoning : reasoning // ignore: cast_nullable_to_non_nullable
as bool,webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as bool,functionCalling: null == functionCalling ? _self.functionCalling : functionCalling // ignore: cast_nullable_to_non_nullable
as bool,parallelToolCalls: null == parallelToolCalls ? _self.parallelToolCalls : parallelToolCalls // ignore: cast_nullable_to_non_nullable
as bool,customTools: null == customTools ? _self.customTools : customTools // ignore: cast_nullable_to_non_nullable
as bool,freeformTools: null == freeformTools ? _self.freeformTools : freeformTools // ignore: cast_nullable_to_non_nullable
as bool,instructionSnapshotOverrides: null == instructionSnapshotOverrides ? _self.instructionSnapshotOverrides : instructionSnapshotOverrides // ignore: cast_nullable_to_non_nullable
as bool,nativeContextFamily: freezed == nativeContextFamily ? _self.nativeContextFamily : nativeContextFamily // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelCapabilities].
extension ModelCapabilitiesPatterns on ModelCapabilities {
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
mixin _$ModelInputCapability {


/// Create a copy of ModelInputCapability
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelInputCapabilityCopyWith<ModelInputCapability> get copyWith => _$ModelInputCapabilityCopyWithImpl<ModelInputCapability>(this as ModelInputCapability, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelInputCapability;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelInputCapability&&(identical(other.modality, _this.modality) || other.modality == _this.modality)&&const DeepCollectionEquality().equals(other.sources, _this.sources)&&(identical(other.maxCount, _this.maxCount) || other.maxCount == _this.maxCount)&&(identical(other.maxBytes, _this.maxBytes) || other.maxBytes == _this.maxBytes)&&(identical(other.maxTotalBytes, _this.maxTotalBytes) || other.maxTotalBytes == _this.maxTotalBytes)&&(identical(other.maxWidth, _this.maxWidth) || other.maxWidth == _this.maxWidth)&&(identical(other.maxHeight, _this.maxHeight) || other.maxHeight == _this.maxHeight)&&const DeepCollectionEquality().equals(other.mediaTypes, _this.mediaTypes));
}


@override
int get hashCode {
  final _this = this as ModelInputCapability;
  return Object.hash(runtimeType,_this.modality,const DeepCollectionEquality().hash(_this.sources),_this.maxCount,_this.maxBytes,_this.maxTotalBytes,_this.maxWidth,_this.maxHeight,const DeepCollectionEquality().hash(_this.mediaTypes));
}

@override
String toString() {
  final _this = this as ModelInputCapability;
  return 'ModelInputCapability(modality: ${_this.modality}, sources: ${_this.sources}, maxCount: ${_this.maxCount}, maxBytes: ${_this.maxBytes}, maxTotalBytes: ${_this.maxTotalBytes}, maxWidth: ${_this.maxWidth}, maxHeight: ${_this.maxHeight}, mediaTypes: ${_this.mediaTypes})';
}


}

/// @nodoc
abstract mixin class $ModelInputCapabilityCopyWith<$Res>  {
  factory $ModelInputCapabilityCopyWith(ModelInputCapability value, $Res Function(ModelInputCapability) _then) = _$ModelInputCapabilityCopyWithImpl;
@useResult
$Res call({
 ModelModality modality, List<ModelInputSource> sources, int? maxCount, int? maxBytes, int? maxTotalBytes, int? maxWidth, int? maxHeight, List<String> mediaTypes
});




}
/// @nodoc
class _$ModelInputCapabilityCopyWithImpl<$Res>
    implements $ModelInputCapabilityCopyWith<$Res> {
  _$ModelInputCapabilityCopyWithImpl(this._self, this._then);

  final ModelInputCapability _self;
  final $Res Function(ModelInputCapability) _then;

/// Create a copy of ModelInputCapability
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modality = null,Object? sources = null,Object? maxCount = freezed,Object? maxBytes = freezed,Object? maxTotalBytes = freezed,Object? maxWidth = freezed,Object? maxHeight = freezed,Object? mediaTypes = null,}) {
  return _then(ModelInputCapability(
modality: null == modality ? _self.modality : modality // ignore: cast_nullable_to_non_nullable
as ModelModality,sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as List<ModelInputSource>,maxCount: freezed == maxCount ? _self.maxCount : maxCount // ignore: cast_nullable_to_non_nullable
as int?,maxBytes: freezed == maxBytes ? _self.maxBytes : maxBytes // ignore: cast_nullable_to_non_nullable
as int?,maxTotalBytes: freezed == maxTotalBytes ? _self.maxTotalBytes : maxTotalBytes // ignore: cast_nullable_to_non_nullable
as int?,maxWidth: freezed == maxWidth ? _self.maxWidth : maxWidth // ignore: cast_nullable_to_non_nullable
as int?,maxHeight: freezed == maxHeight ? _self.maxHeight : maxHeight // ignore: cast_nullable_to_non_nullable
as int?,mediaTypes: null == mediaTypes ? _self.mediaTypes : mediaTypes // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelInputCapability].
extension ModelInputCapabilityPatterns on ModelInputCapability {
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
mixin _$ModelReasoningDescriptor {


/// Create a copy of ModelReasoningDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelReasoningDescriptorCopyWith<ModelReasoningDescriptor> get copyWith => _$ModelReasoningDescriptorCopyWithImpl<ModelReasoningDescriptor>(this as ModelReasoningDescriptor, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelReasoningDescriptor;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelReasoningDescriptor&&(identical(other.parameter, _this.parameter) || other.parameter == _this.parameter)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.defaultValue, _this.defaultValue) || other.defaultValue == _this.defaultValue)&&const DeepCollectionEquality().equals(other.candidates, _this.candidates));
}


@override
int get hashCode {
  final _this = this as ModelReasoningDescriptor;
  return Object.hash(runtimeType,_this.parameter,_this.label,_this.defaultValue,const DeepCollectionEquality().hash(_this.candidates));
}

@override
String toString() {
  final _this = this as ModelReasoningDescriptor;
  return 'ModelReasoningDescriptor(parameter: ${_this.parameter}, label: ${_this.label}, defaultValue: ${_this.defaultValue}, candidates: ${_this.candidates})';
}


}

/// @nodoc
abstract mixin class $ModelReasoningDescriptorCopyWith<$Res>  {
  factory $ModelReasoningDescriptorCopyWith(ModelReasoningDescriptor value, $Res Function(ModelReasoningDescriptor) _then) = _$ModelReasoningDescriptorCopyWithImpl;
@useResult
$Res call({
 String parameter, String label, String? defaultValue, List<String> candidates
});




}
/// @nodoc
class _$ModelReasoningDescriptorCopyWithImpl<$Res>
    implements $ModelReasoningDescriptorCopyWith<$Res> {
  _$ModelReasoningDescriptorCopyWithImpl(this._self, this._then);

  final ModelReasoningDescriptor _self;
  final $Res Function(ModelReasoningDescriptor) _then;

/// Create a copy of ModelReasoningDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? parameter = null,Object? label = null,Object? defaultValue = freezed,Object? candidates = null,}) {
  return _then(ModelReasoningDescriptor(
parameter: null == parameter ? _self.parameter : parameter // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,defaultValue: freezed == defaultValue ? _self.defaultValue : defaultValue // ignore: cast_nullable_to_non_nullable
as String?,candidates: null == candidates ? _self.candidates : candidates // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelReasoningDescriptor].
extension ModelReasoningDescriptorPatterns on ModelReasoningDescriptor {
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
mixin _$ModelPricing {


/// Create a copy of ModelPricing
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelPricingCopyWith<ModelPricing> get copyWith => _$ModelPricingCopyWithImpl<ModelPricing>(this as ModelPricing, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelPricing;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelPricing&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&const DeepCollectionEquality().equals(other.tiers, _this.tiers)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.verifiedAt, _this.verifiedAt) || other.verifiedAt == _this.verifiedAt));
}


@override
int get hashCode {
  final _this = this as ModelPricing;
  return Object.hash(runtimeType,_this.currency,const DeepCollectionEquality().hash(_this.tiers),_this.source,_this.verifiedAt);
}

@override
String toString() {
  final _this = this as ModelPricing;
  return 'ModelPricing(currency: ${_this.currency}, tiers: ${_this.tiers}, source: ${_this.source}, verifiedAt: ${_this.verifiedAt})';
}


}

/// @nodoc
abstract mixin class $ModelPricingCopyWith<$Res>  {
  factory $ModelPricingCopyWith(ModelPricing value, $Res Function(ModelPricing) _then) = _$ModelPricingCopyWithImpl;
@useResult
$Res call({
 String currency, List<ModelPriceTier> tiers, String source, int verifiedAt
});




}
/// @nodoc
class _$ModelPricingCopyWithImpl<$Res>
    implements $ModelPricingCopyWith<$Res> {
  _$ModelPricingCopyWithImpl(this._self, this._then);

  final ModelPricing _self;
  final $Res Function(ModelPricing) _then;

/// Create a copy of ModelPricing
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? currency = null,Object? tiers = null,Object? source = null,Object? verifiedAt = null,}) {
  return _then(ModelPricing(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,tiers: null == tiers ? _self.tiers : tiers // ignore: cast_nullable_to_non_nullable
as List<ModelPriceTier>,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,verifiedAt: null == verifiedAt ? _self.verifiedAt : verifiedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelPricing].
extension ModelPricingPatterns on ModelPricing {
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
mixin _$ModelPriceTier {

 String get label; double get inputPerMtok; double get outputPerMtok; double? get cacheReadPerMtok; double? get cacheWritePerMtok;
/// Create a copy of ModelPriceTier
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelPriceTierCopyWith<ModelPriceTier> get copyWith => _$ModelPriceTierCopyWithImpl<ModelPriceTier>(this as ModelPriceTier, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelPriceTier;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelPriceTier&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.inputPerMtok, _this.inputPerMtok) || other.inputPerMtok == _this.inputPerMtok)&&(identical(other.outputPerMtok, _this.outputPerMtok) || other.outputPerMtok == _this.outputPerMtok)&&(identical(other.cacheReadPerMtok, _this.cacheReadPerMtok) || other.cacheReadPerMtok == _this.cacheReadPerMtok)&&(identical(other.cacheWritePerMtok, _this.cacheWritePerMtok) || other.cacheWritePerMtok == _this.cacheWritePerMtok));
}


@override
int get hashCode {
  final _this = this as ModelPriceTier;
  return Object.hash(runtimeType,_this.label,_this.inputPerMtok,_this.outputPerMtok,_this.cacheReadPerMtok,_this.cacheWritePerMtok);
}

@override
String toString() {
  final _this = this as ModelPriceTier;
  return 'ModelPriceTier(label: ${_this.label}, inputPerMtok: ${_this.inputPerMtok}, outputPerMtok: ${_this.outputPerMtok}, cacheReadPerMtok: ${_this.cacheReadPerMtok}, cacheWritePerMtok: ${_this.cacheWritePerMtok})';
}


}

/// @nodoc
abstract mixin class $ModelPriceTierCopyWith<$Res>  {
  factory $ModelPriceTierCopyWith(ModelPriceTier value, $Res Function(ModelPriceTier) _then) = _$ModelPriceTierCopyWithImpl;
@useResult
$Res call({
 String label, double inputPerMtok, double outputPerMtok, double? cacheReadPerMtok, double? cacheWritePerMtok
});




}
/// @nodoc
class _$ModelPriceTierCopyWithImpl<$Res>
    implements $ModelPriceTierCopyWith<$Res> {
  _$ModelPriceTierCopyWithImpl(this._self, this._then);

  final ModelPriceTier _self;
  final $Res Function(ModelPriceTier) _then;

/// Create a copy of ModelPriceTier
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? inputPerMtok = null,Object? outputPerMtok = null,Object? cacheReadPerMtok = freezed,Object? cacheWritePerMtok = freezed,}) {
  return _then(ModelPriceTier(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,inputPerMtok: null == inputPerMtok ? _self.inputPerMtok : inputPerMtok // ignore: cast_nullable_to_non_nullable
as double,outputPerMtok: null == outputPerMtok ? _self.outputPerMtok : outputPerMtok // ignore: cast_nullable_to_non_nullable
as double,cacheReadPerMtok: freezed == cacheReadPerMtok ? _self.cacheReadPerMtok : cacheReadPerMtok // ignore: cast_nullable_to_non_nullable
as double?,cacheWritePerMtok: freezed == cacheWritePerMtok ? _self.cacheWritePerMtok : cacheWritePerMtok // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelPriceTier].
extension ModelPriceTierPatterns on ModelPriceTier {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelPriceTier value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelPriceTier() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelPriceTier value)  $default,){
final _that = this;
switch (_that) {
case _ModelPriceTier():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelPriceTier value)?  $default,){
final _that = this;
switch (_that) {
case _ModelPriceTier() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String label,  double inputPerMtok,  double outputPerMtok,  double? cacheReadPerMtok,  double? cacheWritePerMtok)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelPriceTier() when $default != null:
return $default(_that.label,_that.inputPerMtok,_that.outputPerMtok,_that.cacheReadPerMtok,_that.cacheWritePerMtok);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String label,  double inputPerMtok,  double outputPerMtok,  double? cacheReadPerMtok,  double? cacheWritePerMtok)  $default,) {final _that = this;
switch (_that) {
case _ModelPriceTier():
return $default(_that.label,_that.inputPerMtok,_that.outputPerMtok,_that.cacheReadPerMtok,_that.cacheWritePerMtok);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String label,  double inputPerMtok,  double outputPerMtok,  double? cacheReadPerMtok,  double? cacheWritePerMtok)?  $default,) {final _that = this;
switch (_that) {
case _ModelPriceTier() when $default != null:
return $default(_that.label,_that.inputPerMtok,_that.outputPerMtok,_that.cacheReadPerMtok,_that.cacheWritePerMtok);case _:
  return null;

}
}

}

/// @nodoc


class _ModelPriceTier implements ModelPriceTier {
  const _ModelPriceTier({required this.label, required this.inputPerMtok, required this.outputPerMtok, required this.cacheReadPerMtok, required this.cacheWritePerMtok});


@override final  String label;
@override final  double inputPerMtok;
@override final  double outputPerMtok;
@override final  double? cacheReadPerMtok;
@override final  double? cacheWritePerMtok;

/// Create a copy of ModelPriceTier
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelPriceTierCopyWith<_ModelPriceTier> get copyWith => __$ModelPriceTierCopyWithImpl<_ModelPriceTier>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelPriceTier&&(identical(other.label, label) || other.label == label)&&(identical(other.inputPerMtok, inputPerMtok) || other.inputPerMtok == inputPerMtok)&&(identical(other.outputPerMtok, outputPerMtok) || other.outputPerMtok == outputPerMtok)&&(identical(other.cacheReadPerMtok, cacheReadPerMtok) || other.cacheReadPerMtok == cacheReadPerMtok)&&(identical(other.cacheWritePerMtok, cacheWritePerMtok) || other.cacheWritePerMtok == cacheWritePerMtok));
}


@override
int get hashCode {
    return Object.hash(runtimeType,label,inputPerMtok,outputPerMtok,cacheReadPerMtok,cacheWritePerMtok);
}

@override
String toString() {
    return 'ModelPriceTier(label: $label, inputPerMtok: $inputPerMtok, outputPerMtok: $outputPerMtok, cacheReadPerMtok: $cacheReadPerMtok, cacheWritePerMtok: $cacheWritePerMtok)';
}


}

/// @nodoc
abstract mixin class _$ModelPriceTierCopyWith<$Res> implements $ModelPriceTierCopyWith<$Res> {
  factory _$ModelPriceTierCopyWith(_ModelPriceTier value, $Res Function(_ModelPriceTier) _then) = __$ModelPriceTierCopyWithImpl;
@override @useResult
$Res call({
 String label, double inputPerMtok, double outputPerMtok, double? cacheReadPerMtok, double? cacheWritePerMtok
});




}
/// @nodoc
class __$ModelPriceTierCopyWithImpl<$Res>
    implements _$ModelPriceTierCopyWith<$Res> {
  __$ModelPriceTierCopyWithImpl(this._self, this._then);

  final _ModelPriceTier _self;
  final $Res Function(_ModelPriceTier) _then;

/// Create a copy of ModelPriceTier
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? inputPerMtok = null,Object? outputPerMtok = null,Object? cacheReadPerMtok = freezed,Object? cacheWritePerMtok = freezed,}) {
  return _then(_ModelPriceTier(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,inputPerMtok: null == inputPerMtok ? _self.inputPerMtok : inputPerMtok // ignore: cast_nullable_to_non_nullable
as double,outputPerMtok: null == outputPerMtok ? _self.outputPerMtok : outputPerMtok // ignore: cast_nullable_to_non_nullable
as double,cacheReadPerMtok: freezed == cacheReadPerMtok ? _self.cacheReadPerMtok : cacheReadPerMtok // ignore: cast_nullable_to_non_nullable
as double?,cacheWritePerMtok: freezed == cacheWritePerMtok ? _self.cacheWritePerMtok : cacheWritePerMtok // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc
mixin _$ModelCatalogError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModelCatalogError()';
}


}

/// @nodoc
class $ModelCatalogErrorCopyWith<$Res>  {
$ModelCatalogErrorCopyWith(ModelCatalogError _, $Res Function(ModelCatalogError) __);
}


/// Adds pattern-matching-related methods to [ModelCatalogError].
extension ModelCatalogErrorPatterns on ModelCatalogError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ModelCatalogUnsupported value)?  unsupported,TResult Function( ModelCatalogConfigurationError value)?  configuration,TResult Function( ModelCatalogTimeout value)?  timeout,TResult Function( ModelCatalogTransportError value)?  transport,TResult Function( ModelCatalogHttpError value)?  http,TResult Function( ModelCatalogTooLarge value)?  tooLarge,TResult Function( ModelCatalogProtocolError value)?  protocol,TResult Function( ModelCatalogCacheIdentity value)?  cacheIdentity,TResult Function( ModelCatalogUnexpectedNotModified value)?  unexpectedNotModified,TResult Function( ModelCatalogCacheWrite value)?  cacheWrite,TResult Function( ModelCatalogClosing value)?  closing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ModelCatalogUnsupported() when unsupported != null:
return unsupported(_that);case ModelCatalogConfigurationError() when configuration != null:
return configuration(_that);case ModelCatalogTimeout() when timeout != null:
return timeout(_that);case ModelCatalogTransportError() when transport != null:
return transport(_that);case ModelCatalogHttpError() when http != null:
return http(_that);case ModelCatalogTooLarge() when tooLarge != null:
return tooLarge(_that);case ModelCatalogProtocolError() when protocol != null:
return protocol(_that);case ModelCatalogCacheIdentity() when cacheIdentity != null:
return cacheIdentity(_that);case ModelCatalogUnexpectedNotModified() when unexpectedNotModified != null:
return unexpectedNotModified(_that);case ModelCatalogCacheWrite() when cacheWrite != null:
return cacheWrite(_that);case ModelCatalogClosing() when closing != null:
return closing(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ModelCatalogUnsupported value)  unsupported,required TResult Function( ModelCatalogConfigurationError value)  configuration,required TResult Function( ModelCatalogTimeout value)  timeout,required TResult Function( ModelCatalogTransportError value)  transport,required TResult Function( ModelCatalogHttpError value)  http,required TResult Function( ModelCatalogTooLarge value)  tooLarge,required TResult Function( ModelCatalogProtocolError value)  protocol,required TResult Function( ModelCatalogCacheIdentity value)  cacheIdentity,required TResult Function( ModelCatalogUnexpectedNotModified value)  unexpectedNotModified,required TResult Function( ModelCatalogCacheWrite value)  cacheWrite,required TResult Function( ModelCatalogClosing value)  closing,}){
final _that = this;
switch (_that) {
case ModelCatalogUnsupported():
return unsupported(_that);case ModelCatalogConfigurationError():
return configuration(_that);case ModelCatalogTimeout():
return timeout(_that);case ModelCatalogTransportError():
return transport(_that);case ModelCatalogHttpError():
return http(_that);case ModelCatalogTooLarge():
return tooLarge(_that);case ModelCatalogProtocolError():
return protocol(_that);case ModelCatalogCacheIdentity():
return cacheIdentity(_that);case ModelCatalogUnexpectedNotModified():
return unexpectedNotModified(_that);case ModelCatalogCacheWrite():
return cacheWrite(_that);case ModelCatalogClosing():
return closing(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ModelCatalogUnsupported value)?  unsupported,TResult? Function( ModelCatalogConfigurationError value)?  configuration,TResult? Function( ModelCatalogTimeout value)?  timeout,TResult? Function( ModelCatalogTransportError value)?  transport,TResult? Function( ModelCatalogHttpError value)?  http,TResult? Function( ModelCatalogTooLarge value)?  tooLarge,TResult? Function( ModelCatalogProtocolError value)?  protocol,TResult? Function( ModelCatalogCacheIdentity value)?  cacheIdentity,TResult? Function( ModelCatalogUnexpectedNotModified value)?  unexpectedNotModified,TResult? Function( ModelCatalogCacheWrite value)?  cacheWrite,TResult? Function( ModelCatalogClosing value)?  closing,}){
final _that = this;
switch (_that) {
case ModelCatalogUnsupported() when unsupported != null:
return unsupported(_that);case ModelCatalogConfigurationError() when configuration != null:
return configuration(_that);case ModelCatalogTimeout() when timeout != null:
return timeout(_that);case ModelCatalogTransportError() when transport != null:
return transport(_that);case ModelCatalogHttpError() when http != null:
return http(_that);case ModelCatalogTooLarge() when tooLarge != null:
return tooLarge(_that);case ModelCatalogProtocolError() when protocol != null:
return protocol(_that);case ModelCatalogCacheIdentity() when cacheIdentity != null:
return cacheIdentity(_that);case ModelCatalogUnexpectedNotModified() when unexpectedNotModified != null:
return unexpectedNotModified(_that);case ModelCatalogCacheWrite() when cacheWrite != null:
return cacheWrite(_that);case ModelCatalogClosing() when closing != null:
return closing(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unsupported,TResult Function()?  configuration,TResult Function()?  timeout,TResult Function( int? httpStatus)?  transport,TResult Function( int status)?  http,TResult Function()?  tooLarge,TResult Function()?  protocol,TResult Function()?  cacheIdentity,TResult Function()?  unexpectedNotModified,TResult Function()?  cacheWrite,TResult Function()?  closing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ModelCatalogUnsupported() when unsupported != null:
return unsupported();case ModelCatalogConfigurationError() when configuration != null:
return configuration();case ModelCatalogTimeout() when timeout != null:
return timeout();case ModelCatalogTransportError() when transport != null:
return transport(_that.httpStatus);case ModelCatalogHttpError() when http != null:
return http(_that.status);case ModelCatalogTooLarge() when tooLarge != null:
return tooLarge();case ModelCatalogProtocolError() when protocol != null:
return protocol();case ModelCatalogCacheIdentity() when cacheIdentity != null:
return cacheIdentity();case ModelCatalogUnexpectedNotModified() when unexpectedNotModified != null:
return unexpectedNotModified();case ModelCatalogCacheWrite() when cacheWrite != null:
return cacheWrite();case ModelCatalogClosing() when closing != null:
return closing();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unsupported,required TResult Function()  configuration,required TResult Function()  timeout,required TResult Function( int? httpStatus)  transport,required TResult Function( int status)  http,required TResult Function()  tooLarge,required TResult Function()  protocol,required TResult Function()  cacheIdentity,required TResult Function()  unexpectedNotModified,required TResult Function()  cacheWrite,required TResult Function()  closing,}) {final _that = this;
switch (_that) {
case ModelCatalogUnsupported():
return unsupported();case ModelCatalogConfigurationError():
return configuration();case ModelCatalogTimeout():
return timeout();case ModelCatalogTransportError():
return transport(_that.httpStatus);case ModelCatalogHttpError():
return http(_that.status);case ModelCatalogTooLarge():
return tooLarge();case ModelCatalogProtocolError():
return protocol();case ModelCatalogCacheIdentity():
return cacheIdentity();case ModelCatalogUnexpectedNotModified():
return unexpectedNotModified();case ModelCatalogCacheWrite():
return cacheWrite();case ModelCatalogClosing():
return closing();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unsupported,TResult? Function()?  configuration,TResult? Function()?  timeout,TResult? Function( int? httpStatus)?  transport,TResult? Function( int status)?  http,TResult? Function()?  tooLarge,TResult? Function()?  protocol,TResult? Function()?  cacheIdentity,TResult? Function()?  unexpectedNotModified,TResult? Function()?  cacheWrite,TResult? Function()?  closing,}) {final _that = this;
switch (_that) {
case ModelCatalogUnsupported() when unsupported != null:
return unsupported();case ModelCatalogConfigurationError() when configuration != null:
return configuration();case ModelCatalogTimeout() when timeout != null:
return timeout();case ModelCatalogTransportError() when transport != null:
return transport(_that.httpStatus);case ModelCatalogHttpError() when http != null:
return http(_that.status);case ModelCatalogTooLarge() when tooLarge != null:
return tooLarge();case ModelCatalogProtocolError() when protocol != null:
return protocol();case ModelCatalogCacheIdentity() when cacheIdentity != null:
return cacheIdentity();case ModelCatalogUnexpectedNotModified() when unexpectedNotModified != null:
return unexpectedNotModified();case ModelCatalogCacheWrite() when cacheWrite != null:
return cacheWrite();case ModelCatalogClosing() when closing != null:
return closing();case _:
  return null;

}
}

}

/// @nodoc


class ModelCatalogUnsupported implements ModelCatalogError {
  const ModelCatalogUnsupported();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogUnsupported);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModelCatalogError.unsupported()';
}


}




/// @nodoc


class ModelCatalogConfigurationError implements ModelCatalogError {
  const ModelCatalogConfigurationError();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogConfigurationError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModelCatalogError.configuration()';
}


}




/// @nodoc


class ModelCatalogTimeout implements ModelCatalogError {
  const ModelCatalogTimeout();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogTimeout);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModelCatalogError.timeout()';
}


}




/// @nodoc


class ModelCatalogTransportError implements ModelCatalogError {
  const ModelCatalogTransportError({required this.httpStatus});


 final  int? httpStatus;

/// Create a copy of ModelCatalogError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogTransportErrorCopyWith<ModelCatalogTransportError> get copyWith => _$ModelCatalogTransportErrorCopyWithImpl<ModelCatalogTransportError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogTransportError&&(identical(other.httpStatus, httpStatus) || other.httpStatus == httpStatus));
}


@override
int get hashCode {
    return Object.hash(runtimeType,httpStatus);
}

@override
String toString() {
    return 'ModelCatalogError.transport(httpStatus: $httpStatus)';
}


}

/// @nodoc
abstract mixin class $ModelCatalogTransportErrorCopyWith<$Res> implements $ModelCatalogErrorCopyWith<$Res> {
  factory $ModelCatalogTransportErrorCopyWith(ModelCatalogTransportError value, $Res Function(ModelCatalogTransportError) _then) = _$ModelCatalogTransportErrorCopyWithImpl;
@useResult
$Res call({
 int? httpStatus
});




}
/// @nodoc
class _$ModelCatalogTransportErrorCopyWithImpl<$Res>
    implements $ModelCatalogTransportErrorCopyWith<$Res> {
  _$ModelCatalogTransportErrorCopyWithImpl(this._self, this._then);

  final ModelCatalogTransportError _self;
  final $Res Function(ModelCatalogTransportError) _then;

/// Create a copy of ModelCatalogError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? httpStatus = freezed,}) {
  return _then(ModelCatalogTransportError(
httpStatus: freezed == httpStatus ? _self.httpStatus : httpStatus // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class ModelCatalogHttpError implements ModelCatalogError {
  const ModelCatalogHttpError({required this.status});


 final  int status;

/// Create a copy of ModelCatalogError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogHttpErrorCopyWith<ModelCatalogHttpError> get copyWith => _$ModelCatalogHttpErrorCopyWithImpl<ModelCatalogHttpError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogHttpError&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status);
}

@override
String toString() {
    return 'ModelCatalogError.http(status: $status)';
}


}

/// @nodoc
abstract mixin class $ModelCatalogHttpErrorCopyWith<$Res> implements $ModelCatalogErrorCopyWith<$Res> {
  factory $ModelCatalogHttpErrorCopyWith(ModelCatalogHttpError value, $Res Function(ModelCatalogHttpError) _then) = _$ModelCatalogHttpErrorCopyWithImpl;
@useResult
$Res call({
 int status
});




}
/// @nodoc
class _$ModelCatalogHttpErrorCopyWithImpl<$Res>
    implements $ModelCatalogHttpErrorCopyWith<$Res> {
  _$ModelCatalogHttpErrorCopyWithImpl(this._self, this._then);

  final ModelCatalogHttpError _self;
  final $Res Function(ModelCatalogHttpError) _then;

/// Create a copy of ModelCatalogError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,}) {
  return _then(ModelCatalogHttpError(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ModelCatalogTooLarge implements ModelCatalogError {
  const ModelCatalogTooLarge();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogTooLarge);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModelCatalogError.tooLarge()';
}


}




/// @nodoc


class ModelCatalogProtocolError implements ModelCatalogError {
  const ModelCatalogProtocolError();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogProtocolError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModelCatalogError.protocol()';
}


}




/// @nodoc


class ModelCatalogCacheIdentity implements ModelCatalogError {
  const ModelCatalogCacheIdentity();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogCacheIdentity);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModelCatalogError.cacheIdentity()';
}


}




/// @nodoc


class ModelCatalogUnexpectedNotModified implements ModelCatalogError {
  const ModelCatalogUnexpectedNotModified();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogUnexpectedNotModified);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModelCatalogError.unexpectedNotModified()';
}


}




/// @nodoc


class ModelCatalogCacheWrite implements ModelCatalogError {
  const ModelCatalogCacheWrite();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogCacheWrite);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModelCatalogError.cacheWrite()';
}


}




/// @nodoc


class ModelCatalogClosing implements ModelCatalogError {
  const ModelCatalogClosing();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogClosing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModelCatalogError.closing()';
}


}




/// @nodoc
mixin _$ModelCatalogStatus {

 bool get supported; ModelCatalogSource get source; bool get probing; int? get lastSuccessAt; int? get checkedAt; ModelCatalogError? get error; ModelCatalogCacheWarning? get cacheWarning;
/// Create a copy of ModelCatalogStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogStatusCopyWith<ModelCatalogStatus> get copyWith => _$ModelCatalogStatusCopyWithImpl<ModelCatalogStatus>(this as ModelCatalogStatus, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelCatalogStatus;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogStatus&&(identical(other.supported, _this.supported) || other.supported == _this.supported)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.probing, _this.probing) || other.probing == _this.probing)&&(identical(other.lastSuccessAt, _this.lastSuccessAt) || other.lastSuccessAt == _this.lastSuccessAt)&&(identical(other.checkedAt, _this.checkedAt) || other.checkedAt == _this.checkedAt)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.cacheWarning, _this.cacheWarning) || other.cacheWarning == _this.cacheWarning));
}


@override
int get hashCode {
  final _this = this as ModelCatalogStatus;
  return Object.hash(runtimeType,_this.supported,_this.source,_this.probing,_this.lastSuccessAt,_this.checkedAt,_this.error,_this.cacheWarning);
}

@override
String toString() {
  final _this = this as ModelCatalogStatus;
  return 'ModelCatalogStatus(supported: ${_this.supported}, source: ${_this.source}, probing: ${_this.probing}, lastSuccessAt: ${_this.lastSuccessAt}, checkedAt: ${_this.checkedAt}, error: ${_this.error}, cacheWarning: ${_this.cacheWarning})';
}


}

/// @nodoc
abstract mixin class $ModelCatalogStatusCopyWith<$Res>  {
  factory $ModelCatalogStatusCopyWith(ModelCatalogStatus value, $Res Function(ModelCatalogStatus) _then) = _$ModelCatalogStatusCopyWithImpl;
@useResult
$Res call({
 bool supported, ModelCatalogSource source, bool probing, int? lastSuccessAt, int? checkedAt, ModelCatalogError? error, ModelCatalogCacheWarning? cacheWarning
});


$ModelCatalogErrorCopyWith<$Res>? get error;

}
/// @nodoc
class _$ModelCatalogStatusCopyWithImpl<$Res>
    implements $ModelCatalogStatusCopyWith<$Res> {
  _$ModelCatalogStatusCopyWithImpl(this._self, this._then);

  final ModelCatalogStatus _self;
  final $Res Function(ModelCatalogStatus) _then;

/// Create a copy of ModelCatalogStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? supported = null,Object? source = null,Object? probing = null,Object? lastSuccessAt = freezed,Object? checkedAt = freezed,Object? error = freezed,Object? cacheWarning = freezed,}) {
  return _then(ModelCatalogStatus(
supported: null == supported ? _self.supported : supported // ignore: cast_nullable_to_non_nullable
as bool,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ModelCatalogSource,probing: null == probing ? _self.probing : probing // ignore: cast_nullable_to_non_nullable
as bool,lastSuccessAt: freezed == lastSuccessAt ? _self.lastSuccessAt : lastSuccessAt // ignore: cast_nullable_to_non_nullable
as int?,checkedAt: freezed == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ModelCatalogError?,cacheWarning: freezed == cacheWarning ? _self.cacheWarning : cacheWarning // ignore: cast_nullable_to_non_nullable
as ModelCatalogCacheWarning?,
  ));
}
/// Create a copy of ModelCatalogStatus
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogErrorCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $ModelCatalogErrorCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelCatalogStatus].
extension ModelCatalogStatusPatterns on ModelCatalogStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelCatalogStatus value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelCatalogStatus() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelCatalogStatus value)  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogStatus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelCatalogStatus value)?  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogStatus() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool supported,  ModelCatalogSource source,  bool probing,  int? lastSuccessAt,  int? checkedAt,  ModelCatalogError? error,  ModelCatalogCacheWarning? cacheWarning)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelCatalogStatus() when $default != null:
return $default(_that.supported,_that.source,_that.probing,_that.lastSuccessAt,_that.checkedAt,_that.error,_that.cacheWarning);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool supported,  ModelCatalogSource source,  bool probing,  int? lastSuccessAt,  int? checkedAt,  ModelCatalogError? error,  ModelCatalogCacheWarning? cacheWarning)  $default,) {final _that = this;
switch (_that) {
case _ModelCatalogStatus():
return $default(_that.supported,_that.source,_that.probing,_that.lastSuccessAt,_that.checkedAt,_that.error,_that.cacheWarning);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool supported,  ModelCatalogSource source,  bool probing,  int? lastSuccessAt,  int? checkedAt,  ModelCatalogError? error,  ModelCatalogCacheWarning? cacheWarning)?  $default,) {final _that = this;
switch (_that) {
case _ModelCatalogStatus() when $default != null:
return $default(_that.supported,_that.source,_that.probing,_that.lastSuccessAt,_that.checkedAt,_that.error,_that.cacheWarning);case _:
  return null;

}
}

}

/// @nodoc


class _ModelCatalogStatus implements ModelCatalogStatus {
  const _ModelCatalogStatus({required this.supported, required this.source, required this.probing, required this.lastSuccessAt, required this.checkedAt, required this.error, required this.cacheWarning});


@override final  bool supported;
@override final  ModelCatalogSource source;
@override final  bool probing;
@override final  int? lastSuccessAt;
@override final  int? checkedAt;
@override final  ModelCatalogError? error;
@override final  ModelCatalogCacheWarning? cacheWarning;

/// Create a copy of ModelCatalogStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelCatalogStatusCopyWith<_ModelCatalogStatus> get copyWith => __$ModelCatalogStatusCopyWithImpl<_ModelCatalogStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCatalogStatus&&(identical(other.supported, supported) || other.supported == supported)&&(identical(other.source, source) || other.source == source)&&(identical(other.probing, probing) || other.probing == probing)&&(identical(other.lastSuccessAt, lastSuccessAt) || other.lastSuccessAt == lastSuccessAt)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.error, error) || other.error == error)&&(identical(other.cacheWarning, cacheWarning) || other.cacheWarning == cacheWarning));
}


@override
int get hashCode {
    return Object.hash(runtimeType,supported,source,probing,lastSuccessAt,checkedAt,error,cacheWarning);
}

@override
String toString() {
    return 'ModelCatalogStatus(supported: $supported, source: $source, probing: $probing, lastSuccessAt: $lastSuccessAt, checkedAt: $checkedAt, error: $error, cacheWarning: $cacheWarning)';
}


}

/// @nodoc
abstract mixin class _$ModelCatalogStatusCopyWith<$Res> implements $ModelCatalogStatusCopyWith<$Res> {
  factory _$ModelCatalogStatusCopyWith(_ModelCatalogStatus value, $Res Function(_ModelCatalogStatus) _then) = __$ModelCatalogStatusCopyWithImpl;
@override @useResult
$Res call({
 bool supported, ModelCatalogSource source, bool probing, int? lastSuccessAt, int? checkedAt, ModelCatalogError? error, ModelCatalogCacheWarning? cacheWarning
});


@override $ModelCatalogErrorCopyWith<$Res>? get error;

}
/// @nodoc
class __$ModelCatalogStatusCopyWithImpl<$Res>
    implements _$ModelCatalogStatusCopyWith<$Res> {
  __$ModelCatalogStatusCopyWithImpl(this._self, this._then);

  final _ModelCatalogStatus _self;
  final $Res Function(_ModelCatalogStatus) _then;

/// Create a copy of ModelCatalogStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? supported = null,Object? source = null,Object? probing = null,Object? lastSuccessAt = freezed,Object? checkedAt = freezed,Object? error = freezed,Object? cacheWarning = freezed,}) {
  return _then(_ModelCatalogStatus(
supported: null == supported ? _self.supported : supported // ignore: cast_nullable_to_non_nullable
as bool,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ModelCatalogSource,probing: null == probing ? _self.probing : probing // ignore: cast_nullable_to_non_nullable
as bool,lastSuccessAt: freezed == lastSuccessAt ? _self.lastSuccessAt : lastSuccessAt // ignore: cast_nullable_to_non_nullable
as int?,checkedAt: freezed == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ModelCatalogError?,cacheWarning: freezed == cacheWarning ? _self.cacheWarning : cacheWarning // ignore: cast_nullable_to_non_nullable
as ModelCatalogCacheWarning?,
  ));
}

/// Create a copy of ModelCatalogStatus
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogErrorCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $ModelCatalogErrorCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$AccountCatalogEntry {


/// Create a copy of AccountCatalogEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountCatalogEntryCopyWith<AccountCatalogEntry> get copyWith => _$AccountCatalogEntryCopyWithImpl<AccountCatalogEntry>(this as AccountCatalogEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountCatalogEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountCatalogEntry&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.credentialRequired, _this.credentialRequired) || other.credentialRequired == _this.credentialRequired)&&(identical(other.capabilitySource, _this.capabilitySource) || other.capabilitySource == _this.capabilitySource)&&(identical(other.hostedWebSearch, _this.hostedWebSearch) || other.hostedWebSearch == _this.hostedWebSearch)&&(identical(other.hostedWebSearchDialect, _this.hostedWebSearchDialect) || other.hostedWebSearchDialect == _this.hostedWebSearchDialect)&&(identical(other.standaloneWebSearch, _this.standaloneWebSearch) || other.standaloneWebSearch == _this.standaloneWebSearch)&&(identical(other.promptCacheDialect, _this.promptCacheDialect) || other.promptCacheDialect == _this.promptCacheDialect)&&(identical(other.responsesProgrammaticToolCalling, _this.responsesProgrammaticToolCalling) || other.responsesProgrammaticToolCalling == _this.responsesProgrammaticToolCalling)&&(identical(other.defaultModelId, _this.defaultModelId) || other.defaultModelId == _this.defaultModelId)&&const DeepCollectionEquality().equals(other.effectiveModels, _this.effectiveModels)&&(identical(other.modelCatalog, _this.modelCatalog) || other.modelCatalog == _this.modelCatalog));
}


@override
int get hashCode {
  final _this = this as AccountCatalogEntry;
  return Object.hash(runtimeType,_this.accountId,_this.credentialRequired,_this.capabilitySource,_this.hostedWebSearch,_this.hostedWebSearchDialect,_this.standaloneWebSearch,_this.promptCacheDialect,_this.responsesProgrammaticToolCalling,_this.defaultModelId,const DeepCollectionEquality().hash(_this.effectiveModels),_this.modelCatalog);
}

@override
String toString() {
  final _this = this as AccountCatalogEntry;
  return 'AccountCatalogEntry(accountId: ${_this.accountId}, credentialRequired: ${_this.credentialRequired}, capabilitySource: ${_this.capabilitySource}, hostedWebSearch: ${_this.hostedWebSearch}, hostedWebSearchDialect: ${_this.hostedWebSearchDialect}, standaloneWebSearch: ${_this.standaloneWebSearch}, promptCacheDialect: ${_this.promptCacheDialect}, responsesProgrammaticToolCalling: ${_this.responsesProgrammaticToolCalling}, defaultModelId: ${_this.defaultModelId}, effectiveModels: ${_this.effectiveModels}, modelCatalog: ${_this.modelCatalog})';
}


}

/// @nodoc
abstract mixin class $AccountCatalogEntryCopyWith<$Res>  {
  factory $AccountCatalogEntryCopyWith(AccountCatalogEntry value, $Res Function(AccountCatalogEntry) _then) = _$AccountCatalogEntryCopyWithImpl;
@useResult
$Res call({
 String accountId, bool credentialRequired, String capabilitySource, bool hostedWebSearch, String hostedWebSearchDialect, String? standaloneWebSearch, String promptCacheDialect, bool responsesProgrammaticToolCalling, String defaultModelId, List<ModelDescriptor> effectiveModels, ModelCatalogStatus modelCatalog
});


$ModelCatalogStatusCopyWith<$Res> get modelCatalog;

}
/// @nodoc
class _$AccountCatalogEntryCopyWithImpl<$Res>
    implements $AccountCatalogEntryCopyWith<$Res> {
  _$AccountCatalogEntryCopyWithImpl(this._self, this._then);

  final AccountCatalogEntry _self;
  final $Res Function(AccountCatalogEntry) _then;

/// Create a copy of AccountCatalogEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? credentialRequired = null,Object? capabilitySource = null,Object? hostedWebSearch = null,Object? hostedWebSearchDialect = null,Object? standaloneWebSearch = freezed,Object? promptCacheDialect = null,Object? responsesProgrammaticToolCalling = null,Object? defaultModelId = null,Object? effectiveModels = null,Object? modelCatalog = null,}) {
  return _then(AccountCatalogEntry(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,credentialRequired: null == credentialRequired ? _self.credentialRequired : credentialRequired // ignore: cast_nullable_to_non_nullable
as bool,capabilitySource: null == capabilitySource ? _self.capabilitySource : capabilitySource // ignore: cast_nullable_to_non_nullable
as String,hostedWebSearch: null == hostedWebSearch ? _self.hostedWebSearch : hostedWebSearch // ignore: cast_nullable_to_non_nullable
as bool,hostedWebSearchDialect: null == hostedWebSearchDialect ? _self.hostedWebSearchDialect : hostedWebSearchDialect // ignore: cast_nullable_to_non_nullable
as String,standaloneWebSearch: freezed == standaloneWebSearch ? _self.standaloneWebSearch : standaloneWebSearch // ignore: cast_nullable_to_non_nullable
as String?,promptCacheDialect: null == promptCacheDialect ? _self.promptCacheDialect : promptCacheDialect // ignore: cast_nullable_to_non_nullable
as String,responsesProgrammaticToolCalling: null == responsesProgrammaticToolCalling ? _self.responsesProgrammaticToolCalling : responsesProgrammaticToolCalling // ignore: cast_nullable_to_non_nullable
as bool,defaultModelId: null == defaultModelId ? _self.defaultModelId : defaultModelId // ignore: cast_nullable_to_non_nullable
as String,effectiveModels: null == effectiveModels ? _self.effectiveModels : effectiveModels // ignore: cast_nullable_to_non_nullable
as List<ModelDescriptor>,modelCatalog: null == modelCatalog ? _self.modelCatalog : modelCatalog // ignore: cast_nullable_to_non_nullable
as ModelCatalogStatus,
  ));
}
/// Create a copy of AccountCatalogEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogStatusCopyWith<$Res> get modelCatalog {

  return $ModelCatalogStatusCopyWith<$Res>(_self.modelCatalog, (value) {
    return _then(_self.copyWith(modelCatalog: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountCatalogEntry].
extension AccountCatalogEntryPatterns on AccountCatalogEntry {
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
mixin _$EffectiveWebSearch {

 String get effectiveMode; String get availability; String? get accountId; String? get modelId;
/// Create a copy of EffectiveWebSearch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EffectiveWebSearchCopyWith<EffectiveWebSearch> get copyWith => _$EffectiveWebSearchCopyWithImpl<EffectiveWebSearch>(this as EffectiveWebSearch, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as EffectiveWebSearch;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EffectiveWebSearch&&(identical(other.effectiveMode, _this.effectiveMode) || other.effectiveMode == _this.effectiveMode)&&(identical(other.availability, _this.availability) || other.availability == _this.availability)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId));
}


@override
int get hashCode {
  final _this = this as EffectiveWebSearch;
  return Object.hash(runtimeType,_this.effectiveMode,_this.availability,_this.accountId,_this.modelId);
}

@override
String toString() {
  final _this = this as EffectiveWebSearch;
  return 'EffectiveWebSearch(effectiveMode: ${_this.effectiveMode}, availability: ${_this.availability}, accountId: ${_this.accountId}, modelId: ${_this.modelId})';
}


}

/// @nodoc
abstract mixin class $EffectiveWebSearchCopyWith<$Res>  {
  factory $EffectiveWebSearchCopyWith(EffectiveWebSearch value, $Res Function(EffectiveWebSearch) _then) = _$EffectiveWebSearchCopyWithImpl;
@useResult
$Res call({
 String effectiveMode, String availability, String? accountId, String? modelId
});




}
/// @nodoc
class _$EffectiveWebSearchCopyWithImpl<$Res>
    implements $EffectiveWebSearchCopyWith<$Res> {
  _$EffectiveWebSearchCopyWithImpl(this._self, this._then);

  final EffectiveWebSearch _self;
  final $Res Function(EffectiveWebSearch) _then;

/// Create a copy of EffectiveWebSearch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? effectiveMode = null,Object? availability = null,Object? accountId = freezed,Object? modelId = freezed,}) {
  return _then(EffectiveWebSearch(
effectiveMode: null == effectiveMode ? _self.effectiveMode : effectiveMode // ignore: cast_nullable_to_non_nullable
as String,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as String,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,modelId: freezed == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [EffectiveWebSearch].
extension EffectiveWebSearchPatterns on EffectiveWebSearch {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EffectiveWebSearch value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EffectiveWebSearch() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EffectiveWebSearch value)  $default,){
final _that = this;
switch (_that) {
case _EffectiveWebSearch():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EffectiveWebSearch value)?  $default,){
final _that = this;
switch (_that) {
case _EffectiveWebSearch() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String effectiveMode,  String availability,  String? accountId,  String? modelId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EffectiveWebSearch() when $default != null:
return $default(_that.effectiveMode,_that.availability,_that.accountId,_that.modelId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String effectiveMode,  String availability,  String? accountId,  String? modelId)  $default,) {final _that = this;
switch (_that) {
case _EffectiveWebSearch():
return $default(_that.effectiveMode,_that.availability,_that.accountId,_that.modelId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String effectiveMode,  String availability,  String? accountId,  String? modelId)?  $default,) {final _that = this;
switch (_that) {
case _EffectiveWebSearch() when $default != null:
return $default(_that.effectiveMode,_that.availability,_that.accountId,_that.modelId);case _:
  return null;

}
}

}

/// @nodoc


class _EffectiveWebSearch implements EffectiveWebSearch {
  const _EffectiveWebSearch({required this.effectiveMode, required this.availability, required this.accountId, required this.modelId});


@override final  String effectiveMode;
@override final  String availability;
@override final  String? accountId;
@override final  String? modelId;

/// Create a copy of EffectiveWebSearch
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EffectiveWebSearchCopyWith<_EffectiveWebSearch> get copyWith => __$EffectiveWebSearchCopyWithImpl<_EffectiveWebSearch>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _EffectiveWebSearch&&(identical(other.effectiveMode, effectiveMode) || other.effectiveMode == effectiveMode)&&(identical(other.availability, availability) || other.availability == availability)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,effectiveMode,availability,accountId,modelId);
}

@override
String toString() {
    return 'EffectiveWebSearch(effectiveMode: $effectiveMode, availability: $availability, accountId: $accountId, modelId: $modelId)';
}


}

/// @nodoc
abstract mixin class _$EffectiveWebSearchCopyWith<$Res> implements $EffectiveWebSearchCopyWith<$Res> {
  factory _$EffectiveWebSearchCopyWith(_EffectiveWebSearch value, $Res Function(_EffectiveWebSearch) _then) = __$EffectiveWebSearchCopyWithImpl;
@override @useResult
$Res call({
 String effectiveMode, String availability, String? accountId, String? modelId
});




}
/// @nodoc
class __$EffectiveWebSearchCopyWithImpl<$Res>
    implements _$EffectiveWebSearchCopyWith<$Res> {
  __$EffectiveWebSearchCopyWithImpl(this._self, this._then);

  final _EffectiveWebSearch _self;
  final $Res Function(_EffectiveWebSearch) _then;

/// Create a copy of EffectiveWebSearch
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? effectiveMode = null,Object? availability = null,Object? accountId = freezed,Object? modelId = freezed,}) {
  return _then(_EffectiveWebSearch(
effectiveMode: null == effectiveMode ? _self.effectiveMode : effectiveMode // ignore: cast_nullable_to_non_nullable
as String,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as String,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,modelId: freezed == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$EffectiveDeepSeekSearch {

 bool get effectiveEnabled; bool get effectiveFetchEnabled; String get availability; String? get accountId;
/// Create a copy of EffectiveDeepSeekSearch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EffectiveDeepSeekSearchCopyWith<EffectiveDeepSeekSearch> get copyWith => _$EffectiveDeepSeekSearchCopyWithImpl<EffectiveDeepSeekSearch>(this as EffectiveDeepSeekSearch, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as EffectiveDeepSeekSearch;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EffectiveDeepSeekSearch&&(identical(other.effectiveEnabled, _this.effectiveEnabled) || other.effectiveEnabled == _this.effectiveEnabled)&&(identical(other.effectiveFetchEnabled, _this.effectiveFetchEnabled) || other.effectiveFetchEnabled == _this.effectiveFetchEnabled)&&(identical(other.availability, _this.availability) || other.availability == _this.availability)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId));
}


@override
int get hashCode {
  final _this = this as EffectiveDeepSeekSearch;
  return Object.hash(runtimeType,_this.effectiveEnabled,_this.effectiveFetchEnabled,_this.availability,_this.accountId);
}

@override
String toString() {
  final _this = this as EffectiveDeepSeekSearch;
  return 'EffectiveDeepSeekSearch(effectiveEnabled: ${_this.effectiveEnabled}, effectiveFetchEnabled: ${_this.effectiveFetchEnabled}, availability: ${_this.availability}, accountId: ${_this.accountId})';
}


}

/// @nodoc
abstract mixin class $EffectiveDeepSeekSearchCopyWith<$Res>  {
  factory $EffectiveDeepSeekSearchCopyWith(EffectiveDeepSeekSearch value, $Res Function(EffectiveDeepSeekSearch) _then) = _$EffectiveDeepSeekSearchCopyWithImpl;
@useResult
$Res call({
 bool effectiveEnabled, bool effectiveFetchEnabled, String availability, String? accountId
});




}
/// @nodoc
class _$EffectiveDeepSeekSearchCopyWithImpl<$Res>
    implements $EffectiveDeepSeekSearchCopyWith<$Res> {
  _$EffectiveDeepSeekSearchCopyWithImpl(this._self, this._then);

  final EffectiveDeepSeekSearch _self;
  final $Res Function(EffectiveDeepSeekSearch) _then;

/// Create a copy of EffectiveDeepSeekSearch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? effectiveEnabled = null,Object? effectiveFetchEnabled = null,Object? availability = null,Object? accountId = freezed,}) {
  return _then(EffectiveDeepSeekSearch(
effectiveEnabled: null == effectiveEnabled ? _self.effectiveEnabled : effectiveEnabled // ignore: cast_nullable_to_non_nullable
as bool,effectiveFetchEnabled: null == effectiveFetchEnabled ? _self.effectiveFetchEnabled : effectiveFetchEnabled // ignore: cast_nullable_to_non_nullable
as bool,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as String,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [EffectiveDeepSeekSearch].
extension EffectiveDeepSeekSearchPatterns on EffectiveDeepSeekSearch {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EffectiveDeepSeekSearch value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearch() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EffectiveDeepSeekSearch value)  $default,){
final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearch():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EffectiveDeepSeekSearch value)?  $default,){
final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearch() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool effectiveEnabled,  bool effectiveFetchEnabled,  String availability,  String? accountId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearch() when $default != null:
return $default(_that.effectiveEnabled,_that.effectiveFetchEnabled,_that.availability,_that.accountId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool effectiveEnabled,  bool effectiveFetchEnabled,  String availability,  String? accountId)  $default,) {final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearch():
return $default(_that.effectiveEnabled,_that.effectiveFetchEnabled,_that.availability,_that.accountId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool effectiveEnabled,  bool effectiveFetchEnabled,  String availability,  String? accountId)?  $default,) {final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearch() when $default != null:
return $default(_that.effectiveEnabled,_that.effectiveFetchEnabled,_that.availability,_that.accountId);case _:
  return null;

}
}

}

/// @nodoc


class _EffectiveDeepSeekSearch implements EffectiveDeepSeekSearch {
  const _EffectiveDeepSeekSearch({required this.effectiveEnabled, required this.effectiveFetchEnabled, required this.availability, required this.accountId});


@override final  bool effectiveEnabled;
@override final  bool effectiveFetchEnabled;
@override final  String availability;
@override final  String? accountId;

/// Create a copy of EffectiveDeepSeekSearch
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EffectiveDeepSeekSearchCopyWith<_EffectiveDeepSeekSearch> get copyWith => __$EffectiveDeepSeekSearchCopyWithImpl<_EffectiveDeepSeekSearch>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _EffectiveDeepSeekSearch&&(identical(other.effectiveEnabled, effectiveEnabled) || other.effectiveEnabled == effectiveEnabled)&&(identical(other.effectiveFetchEnabled, effectiveFetchEnabled) || other.effectiveFetchEnabled == effectiveFetchEnabled)&&(identical(other.availability, availability) || other.availability == availability)&&(identical(other.accountId, accountId) || other.accountId == accountId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,effectiveEnabled,effectiveFetchEnabled,availability,accountId);
}

@override
String toString() {
    return 'EffectiveDeepSeekSearch(effectiveEnabled: $effectiveEnabled, effectiveFetchEnabled: $effectiveFetchEnabled, availability: $availability, accountId: $accountId)';
}


}

/// @nodoc
abstract mixin class _$EffectiveDeepSeekSearchCopyWith<$Res> implements $EffectiveDeepSeekSearchCopyWith<$Res> {
  factory _$EffectiveDeepSeekSearchCopyWith(_EffectiveDeepSeekSearch value, $Res Function(_EffectiveDeepSeekSearch) _then) = __$EffectiveDeepSeekSearchCopyWithImpl;
@override @useResult
$Res call({
 bool effectiveEnabled, bool effectiveFetchEnabled, String availability, String? accountId
});




}
/// @nodoc
class __$EffectiveDeepSeekSearchCopyWithImpl<$Res>
    implements _$EffectiveDeepSeekSearchCopyWith<$Res> {
  __$EffectiveDeepSeekSearchCopyWithImpl(this._self, this._then);

  final _EffectiveDeepSeekSearch _self;
  final $Res Function(_EffectiveDeepSeekSearch) _then;

/// Create a copy of EffectiveDeepSeekSearch
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? effectiveEnabled = null,Object? effectiveFetchEnabled = null,Object? availability = null,Object? accountId = freezed,}) {
  return _then(_EffectiveDeepSeekSearch(
effectiveEnabled: null == effectiveEnabled ? _self.effectiveEnabled : effectiveEnabled // ignore: cast_nullable_to_non_nullable
as bool,effectiveFetchEnabled: null == effectiveFetchEnabled ? _self.effectiveFetchEnabled : effectiveFetchEnabled // ignore: cast_nullable_to_non_nullable
as bool,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as String,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$ModelsValue {


/// Create a copy of ModelsValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelsValueCopyWith<ModelsValue> get copyWith => _$ModelsValueCopyWithImpl<ModelsValue>(this as ModelsValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelsValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelsValue&&const DeepCollectionEquality().equals(other.accounts, _this.accounts)&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.deepseekWebSearch, _this.deepseekWebSearch) || other.deepseekWebSearch == _this.deepseekWebSearch));
}


@override
int get hashCode {
  final _this = this as ModelsValue;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.accounts),_this.webSearch,_this.deepseekWebSearch);
}

@override
String toString() {
  final _this = this as ModelsValue;
  return 'ModelsValue(accounts: ${_this.accounts}, webSearch: ${_this.webSearch}, deepseekWebSearch: ${_this.deepseekWebSearch})';
}


}

/// @nodoc
abstract mixin class $ModelsValueCopyWith<$Res>  {
  factory $ModelsValueCopyWith(ModelsValue value, $Res Function(ModelsValue) _then) = _$ModelsValueCopyWithImpl;
@useResult
$Res call({
 List<AccountCatalogEntry> accounts, EffectiveWebSearch webSearch, EffectiveDeepSeekSearch deepseekWebSearch
});


$EffectiveWebSearchCopyWith<$Res> get webSearch;$EffectiveDeepSeekSearchCopyWith<$Res> get deepseekWebSearch;

}
/// @nodoc
class _$ModelsValueCopyWithImpl<$Res>
    implements $ModelsValueCopyWith<$Res> {
  _$ModelsValueCopyWithImpl(this._self, this._then);

  final ModelsValue _self;
  final $Res Function(ModelsValue) _then;

/// Create a copy of ModelsValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accounts = null,Object? webSearch = null,Object? deepseekWebSearch = null,}) {
  return _then(ModelsValue(
accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<AccountCatalogEntry>,webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as EffectiveWebSearch,deepseekWebSearch: null == deepseekWebSearch ? _self.deepseekWebSearch : deepseekWebSearch // ignore: cast_nullable_to_non_nullable
as EffectiveDeepSeekSearch,
  ));
}
/// Create a copy of ModelsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveWebSearchCopyWith<$Res> get webSearch {

  return $EffectiveWebSearchCopyWith<$Res>(_self.webSearch, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of ModelsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveDeepSeekSearchCopyWith<$Res> get deepseekWebSearch {

  return $EffectiveDeepSeekSearchCopyWith<$Res>(_self.deepseekWebSearch, (value) {
    return _then(_self.copyWith(deepseekWebSearch: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelsValue].
extension ModelsValuePatterns on ModelsValue {
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

// dart format on
