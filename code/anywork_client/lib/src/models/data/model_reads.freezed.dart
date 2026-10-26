// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModelDescriptorRead {

 ReadText get modelId; bool get enabled; TypedListRef get typeSupport; ModelOrigin get origin; ReadText get displayName; ReadText? get description; int? get contextWindow; int? get maxContextWindow; ModelContextResolutionRead get context; int? get maxOutputTokens; ModelTransportDescriptorRead get transport; ModelCapabilitiesRead get capabilities; ModelReasoningDescriptorRead? get reasoning; ModelPricingRead? get pricing;
/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelDescriptorReadCopyWith<ModelDescriptorRead> get copyWith => _$ModelDescriptorReadCopyWithImpl<ModelDescriptorRead>(this as ModelDescriptorRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelDescriptorRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelDescriptorRead&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.typeSupport, _this.typeSupport) || other.typeSupport == _this.typeSupport)&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.maxContextWindow, _this.maxContextWindow) || other.maxContextWindow == _this.maxContextWindow)&&(identical(other.context, _this.context) || other.context == _this.context)&&(identical(other.maxOutputTokens, _this.maxOutputTokens) || other.maxOutputTokens == _this.maxOutputTokens)&&(identical(other.transport, _this.transport) || other.transport == _this.transport)&&(identical(other.capabilities, _this.capabilities) || other.capabilities == _this.capabilities)&&(identical(other.reasoning, _this.reasoning) || other.reasoning == _this.reasoning)&&(identical(other.pricing, _this.pricing) || other.pricing == _this.pricing));
}


@override
int get hashCode {
  final _this = this as ModelDescriptorRead;
  return Object.hash(runtimeType,_this.modelId,_this.enabled,_this.typeSupport,_this.origin,_this.displayName,_this.description,_this.contextWindow,_this.maxContextWindow,_this.context,_this.maxOutputTokens,_this.transport,_this.capabilities,_this.reasoning,_this.pricing);
}



}

/// @nodoc
abstract mixin class $ModelDescriptorReadCopyWith<$Res>  {
  factory $ModelDescriptorReadCopyWith(ModelDescriptorRead value, $Res Function(ModelDescriptorRead) _then) = _$ModelDescriptorReadCopyWithImpl;
@useResult
$Res call({
 ReadText modelId, bool enabled, TypedListRef typeSupport, ModelOrigin origin, ReadText displayName, ReadText? description, int? contextWindow, int? maxContextWindow, ModelContextResolutionRead context, int? maxOutputTokens, ModelTransportDescriptorRead transport, ModelCapabilitiesRead capabilities, ModelReasoningDescriptorRead? reasoning, ModelPricingRead? pricing
});


$ReadTextCopyWith<$Res> get modelId;$TypedListRefCopyWith<$Res> get typeSupport;$ReadTextCopyWith<$Res> get displayName;$ReadTextCopyWith<$Res>? get description;$ModelContextResolutionReadCopyWith<$Res> get context;$ModelTransportDescriptorReadCopyWith<$Res> get transport;$ModelCapabilitiesReadCopyWith<$Res> get capabilities;$ModelReasoningDescriptorReadCopyWith<$Res>? get reasoning;$ModelPricingReadCopyWith<$Res>? get pricing;

}
/// @nodoc
class _$ModelDescriptorReadCopyWithImpl<$Res>
    implements $ModelDescriptorReadCopyWith<$Res> {
  _$ModelDescriptorReadCopyWithImpl(this._self, this._then);

  final ModelDescriptorRead _self;
  final $Res Function(ModelDescriptorRead) _then;

/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelId = null,Object? enabled = null,Object? typeSupport = null,Object? origin = null,Object? displayName = null,Object? description = freezed,Object? contextWindow = freezed,Object? maxContextWindow = freezed,Object? context = null,Object? maxOutputTokens = freezed,Object? transport = null,Object? capabilities = null,Object? reasoning = freezed,Object? pricing = freezed,}) {
  return _then(ModelDescriptorRead(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,typeSupport: null == typeSupport ? _self.typeSupport : typeSupport // ignore: cast_nullable_to_non_nullable
as TypedListRef,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ModelOrigin,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText?,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxContextWindow: freezed == maxContextWindow ? _self.maxContextWindow : maxContextWindow // ignore: cast_nullable_to_non_nullable
as int?,context: null == context ? _self.context : context // ignore: cast_nullable_to_non_nullable
as ModelContextResolutionRead,maxOutputTokens: freezed == maxOutputTokens ? _self.maxOutputTokens : maxOutputTokens // ignore: cast_nullable_to_non_nullable
as int?,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as ModelTransportDescriptorRead,capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as ModelCapabilitiesRead,reasoning: freezed == reasoning ? _self.reasoning : reasoning // ignore: cast_nullable_to_non_nullable
as ModelReasoningDescriptorRead?,pricing: freezed == pricing ? _self.pricing : pricing // ignore: cast_nullable_to_non_nullable
as ModelPricingRead?,
  ));
}
/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get typeSupport {

  return $TypedListRefCopyWith<$Res>(_self.typeSupport, (value) {
    return _then(_self.copyWith(typeSupport: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get description {
    if (_self.description == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.description!, (value) {
    return _then(_self.copyWith(description: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelContextResolutionReadCopyWith<$Res> get context {

  return $ModelContextResolutionReadCopyWith<$Res>(_self.context, (value) {
    return _then(_self.copyWith(context: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelTransportDescriptorReadCopyWith<$Res> get transport {

  return $ModelTransportDescriptorReadCopyWith<$Res>(_self.transport, (value) {
    return _then(_self.copyWith(transport: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCapabilitiesReadCopyWith<$Res> get capabilities {

  return $ModelCapabilitiesReadCopyWith<$Res>(_self.capabilities, (value) {
    return _then(_self.copyWith(capabilities: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelReasoningDescriptorReadCopyWith<$Res>? get reasoning {
    if (_self.reasoning == null) {
    return null;
  }

  return $ModelReasoningDescriptorReadCopyWith<$Res>(_self.reasoning!, (value) {
    return _then(_self.copyWith(reasoning: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelPricingReadCopyWith<$Res>? get pricing {
    if (_self.pricing == null) {
    return null;
  }

  return $ModelPricingReadCopyWith<$Res>(_self.pricing!, (value) {
    return _then(_self.copyWith(pricing: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelDescriptorRead].
extension ModelDescriptorReadPatterns on ModelDescriptorRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelDescriptorRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelDescriptorRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelDescriptorRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelDescriptorRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelDescriptorRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelDescriptorRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText modelId,  bool enabled,  TypedListRef typeSupport,  ModelOrigin origin,  ReadText displayName,  ReadText? description,  int? contextWindow,  int? maxContextWindow,  ModelContextResolutionRead context,  int? maxOutputTokens,  ModelTransportDescriptorRead transport,  ModelCapabilitiesRead capabilities,  ModelReasoningDescriptorRead? reasoning,  ModelPricingRead? pricing)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelDescriptorRead() when $default != null:
return $default(_that.modelId,_that.enabled,_that.typeSupport,_that.origin,_that.displayName,_that.description,_that.contextWindow,_that.maxContextWindow,_that.context,_that.maxOutputTokens,_that.transport,_that.capabilities,_that.reasoning,_that.pricing);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText modelId,  bool enabled,  TypedListRef typeSupport,  ModelOrigin origin,  ReadText displayName,  ReadText? description,  int? contextWindow,  int? maxContextWindow,  ModelContextResolutionRead context,  int? maxOutputTokens,  ModelTransportDescriptorRead transport,  ModelCapabilitiesRead capabilities,  ModelReasoningDescriptorRead? reasoning,  ModelPricingRead? pricing)  $default,) {final _that = this;
switch (_that) {
case _ModelDescriptorRead():
return $default(_that.modelId,_that.enabled,_that.typeSupport,_that.origin,_that.displayName,_that.description,_that.contextWindow,_that.maxContextWindow,_that.context,_that.maxOutputTokens,_that.transport,_that.capabilities,_that.reasoning,_that.pricing);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText modelId,  bool enabled,  TypedListRef typeSupport,  ModelOrigin origin,  ReadText displayName,  ReadText? description,  int? contextWindow,  int? maxContextWindow,  ModelContextResolutionRead context,  int? maxOutputTokens,  ModelTransportDescriptorRead transport,  ModelCapabilitiesRead capabilities,  ModelReasoningDescriptorRead? reasoning,  ModelPricingRead? pricing)?  $default,) {final _that = this;
switch (_that) {
case _ModelDescriptorRead() when $default != null:
return $default(_that.modelId,_that.enabled,_that.typeSupport,_that.origin,_that.displayName,_that.description,_that.contextWindow,_that.maxContextWindow,_that.context,_that.maxOutputTokens,_that.transport,_that.capabilities,_that.reasoning,_that.pricing);case _:
  return null;

}
}

}

/// @nodoc


class _ModelDescriptorRead implements ModelDescriptorRead {
  const _ModelDescriptorRead({required this.modelId, required this.enabled, required this.typeSupport, required this.origin, required this.displayName, required this.description, required this.contextWindow, required this.maxContextWindow, required this.context, required this.maxOutputTokens, required this.transport, required this.capabilities, required this.reasoning, required this.pricing});


@override final  ReadText modelId;
@override final  bool enabled;
@override final  TypedListRef typeSupport;
@override final  ModelOrigin origin;
@override final  ReadText displayName;
@override final  ReadText? description;
@override final  int? contextWindow;
@override final  int? maxContextWindow;
@override final  ModelContextResolutionRead context;
@override final  int? maxOutputTokens;
@override final  ModelTransportDescriptorRead transport;
@override final  ModelCapabilitiesRead capabilities;
@override final  ModelReasoningDescriptorRead? reasoning;
@override final  ModelPricingRead? pricing;

/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelDescriptorReadCopyWith<_ModelDescriptorRead> get copyWith => __$ModelDescriptorReadCopyWithImpl<_ModelDescriptorRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelDescriptorRead&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.typeSupport, typeSupport) || other.typeSupport == typeSupport)&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.contextWindow, contextWindow) || other.contextWindow == contextWindow)&&(identical(other.maxContextWindow, maxContextWindow) || other.maxContextWindow == maxContextWindow)&&(identical(other.context, context) || other.context == context)&&(identical(other.maxOutputTokens, maxOutputTokens) || other.maxOutputTokens == maxOutputTokens)&&(identical(other.transport, transport) || other.transport == transport)&&(identical(other.capabilities, capabilities) || other.capabilities == capabilities)&&(identical(other.reasoning, reasoning) || other.reasoning == reasoning)&&(identical(other.pricing, pricing) || other.pricing == pricing));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelId,enabled,typeSupport,origin,displayName,description,contextWindow,maxContextWindow,context,maxOutputTokens,transport,capabilities,reasoning,pricing);
}



}

/// @nodoc
abstract mixin class _$ModelDescriptorReadCopyWith<$Res> implements $ModelDescriptorReadCopyWith<$Res> {
  factory _$ModelDescriptorReadCopyWith(_ModelDescriptorRead value, $Res Function(_ModelDescriptorRead) _then) = __$ModelDescriptorReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText modelId, bool enabled, TypedListRef typeSupport, ModelOrigin origin, ReadText displayName, ReadText? description, int? contextWindow, int? maxContextWindow, ModelContextResolutionRead context, int? maxOutputTokens, ModelTransportDescriptorRead transport, ModelCapabilitiesRead capabilities, ModelReasoningDescriptorRead? reasoning, ModelPricingRead? pricing
});


@override $ReadTextCopyWith<$Res> get modelId;@override $TypedListRefCopyWith<$Res> get typeSupport;@override $ReadTextCopyWith<$Res> get displayName;@override $ReadTextCopyWith<$Res>? get description;@override $ModelContextResolutionReadCopyWith<$Res> get context;@override $ModelTransportDescriptorReadCopyWith<$Res> get transport;@override $ModelCapabilitiesReadCopyWith<$Res> get capabilities;@override $ModelReasoningDescriptorReadCopyWith<$Res>? get reasoning;@override $ModelPricingReadCopyWith<$Res>? get pricing;

}
/// @nodoc
class __$ModelDescriptorReadCopyWithImpl<$Res>
    implements _$ModelDescriptorReadCopyWith<$Res> {
  __$ModelDescriptorReadCopyWithImpl(this._self, this._then);

  final _ModelDescriptorRead _self;
  final $Res Function(_ModelDescriptorRead) _then;

/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelId = null,Object? enabled = null,Object? typeSupport = null,Object? origin = null,Object? displayName = null,Object? description = freezed,Object? contextWindow = freezed,Object? maxContextWindow = freezed,Object? context = null,Object? maxOutputTokens = freezed,Object? transport = null,Object? capabilities = null,Object? reasoning = freezed,Object? pricing = freezed,}) {
  return _then(_ModelDescriptorRead(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,typeSupport: null == typeSupport ? _self.typeSupport : typeSupport // ignore: cast_nullable_to_non_nullable
as TypedListRef,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ModelOrigin,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText?,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,maxContextWindow: freezed == maxContextWindow ? _self.maxContextWindow : maxContextWindow // ignore: cast_nullable_to_non_nullable
as int?,context: null == context ? _self.context : context // ignore: cast_nullable_to_non_nullable
as ModelContextResolutionRead,maxOutputTokens: freezed == maxOutputTokens ? _self.maxOutputTokens : maxOutputTokens // ignore: cast_nullable_to_non_nullable
as int?,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as ModelTransportDescriptorRead,capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as ModelCapabilitiesRead,reasoning: freezed == reasoning ? _self.reasoning : reasoning // ignore: cast_nullable_to_non_nullable
as ModelReasoningDescriptorRead?,pricing: freezed == pricing ? _self.pricing : pricing // ignore: cast_nullable_to_non_nullable
as ModelPricingRead?,
  ));
}

/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get typeSupport {

  return $TypedListRefCopyWith<$Res>(_self.typeSupport, (value) {
    return _then(_self.copyWith(typeSupport: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get description {
    if (_self.description == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.description!, (value) {
    return _then(_self.copyWith(description: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelContextResolutionReadCopyWith<$Res> get context {

  return $ModelContextResolutionReadCopyWith<$Res>(_self.context, (value) {
    return _then(_self.copyWith(context: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelTransportDescriptorReadCopyWith<$Res> get transport {

  return $ModelTransportDescriptorReadCopyWith<$Res>(_self.transport, (value) {
    return _then(_self.copyWith(transport: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCapabilitiesReadCopyWith<$Res> get capabilities {

  return $ModelCapabilitiesReadCopyWith<$Res>(_self.capabilities, (value) {
    return _then(_self.copyWith(capabilities: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelReasoningDescriptorReadCopyWith<$Res>? get reasoning {
    if (_self.reasoning == null) {
    return null;
  }

  return $ModelReasoningDescriptorReadCopyWith<$Res>(_self.reasoning!, (value) {
    return _then(_self.copyWith(reasoning: value));
  });
}/// Create a copy of ModelDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelPricingReadCopyWith<$Res>? get pricing {
    if (_self.pricing == null) {
    return null;
  }

  return $ModelPricingReadCopyWith<$Res>(_self.pricing!, (value) {
    return _then(_self.copyWith(pricing: value));
  });
}
}

/// @nodoc
mixin _$ModelTypeSupportRead {

 ModelType get modelType; TypedListRef get exclusions;
/// Create a copy of ModelTypeSupportRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelTypeSupportReadCopyWith<ModelTypeSupportRead> get copyWith => _$ModelTypeSupportReadCopyWithImpl<ModelTypeSupportRead>(this as ModelTypeSupportRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelTypeSupportRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelTypeSupportRead&&(identical(other.modelType, _this.modelType) || other.modelType == _this.modelType)&&(identical(other.exclusions, _this.exclusions) || other.exclusions == _this.exclusions));
}


@override
int get hashCode {
  final _this = this as ModelTypeSupportRead;
  return Object.hash(runtimeType,_this.modelType,_this.exclusions);
}

@override
String toString() {
  final _this = this as ModelTypeSupportRead;
  return 'ModelTypeSupportRead(modelType: ${_this.modelType}, exclusions: ${_this.exclusions})';
}


}

/// @nodoc
abstract mixin class $ModelTypeSupportReadCopyWith<$Res>  {
  factory $ModelTypeSupportReadCopyWith(ModelTypeSupportRead value, $Res Function(ModelTypeSupportRead) _then) = _$ModelTypeSupportReadCopyWithImpl;
@useResult
$Res call({
 ModelType modelType, TypedListRef exclusions
});


$TypedListRefCopyWith<$Res> get exclusions;

}
/// @nodoc
class _$ModelTypeSupportReadCopyWithImpl<$Res>
    implements $ModelTypeSupportReadCopyWith<$Res> {
  _$ModelTypeSupportReadCopyWithImpl(this._self, this._then);

  final ModelTypeSupportRead _self;
  final $Res Function(ModelTypeSupportRead) _then;

/// Create a copy of ModelTypeSupportRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelType = null,Object? exclusions = null,}) {
  return _then(ModelTypeSupportRead(
modelType: null == modelType ? _self.modelType : modelType // ignore: cast_nullable_to_non_nullable
as ModelType,exclusions: null == exclusions ? _self.exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of ModelTypeSupportRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get exclusions {

  return $TypedListRefCopyWith<$Res>(_self.exclusions, (value) {
    return _then(_self.copyWith(exclusions: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelTypeSupportRead].
extension ModelTypeSupportReadPatterns on ModelTypeSupportRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelTypeSupportRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelTypeSupportRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelTypeSupportRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelTypeSupportRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelTypeSupportRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelTypeSupportRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModelType modelType,  TypedListRef exclusions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelTypeSupportRead() when $default != null:
return $default(_that.modelType,_that.exclusions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModelType modelType,  TypedListRef exclusions)  $default,) {final _that = this;
switch (_that) {
case _ModelTypeSupportRead():
return $default(_that.modelType,_that.exclusions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModelType modelType,  TypedListRef exclusions)?  $default,) {final _that = this;
switch (_that) {
case _ModelTypeSupportRead() when $default != null:
return $default(_that.modelType,_that.exclusions);case _:
  return null;

}
}

}

/// @nodoc


class _ModelTypeSupportRead implements ModelTypeSupportRead {
  const _ModelTypeSupportRead({required this.modelType, required this.exclusions});


@override final  ModelType modelType;
@override final  TypedListRef exclusions;

/// Create a copy of ModelTypeSupportRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelTypeSupportReadCopyWith<_ModelTypeSupportRead> get copyWith => __$ModelTypeSupportReadCopyWithImpl<_ModelTypeSupportRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelTypeSupportRead&&(identical(other.modelType, modelType) || other.modelType == modelType)&&(identical(other.exclusions, exclusions) || other.exclusions == exclusions));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelType,exclusions);
}

@override
String toString() {
    return 'ModelTypeSupportRead(modelType: $modelType, exclusions: $exclusions)';
}


}

/// @nodoc
abstract mixin class _$ModelTypeSupportReadCopyWith<$Res> implements $ModelTypeSupportReadCopyWith<$Res> {
  factory _$ModelTypeSupportReadCopyWith(_ModelTypeSupportRead value, $Res Function(_ModelTypeSupportRead) _then) = __$ModelTypeSupportReadCopyWithImpl;
@override @useResult
$Res call({
 ModelType modelType, TypedListRef exclusions
});


@override $TypedListRefCopyWith<$Res> get exclusions;

}
/// @nodoc
class __$ModelTypeSupportReadCopyWithImpl<$Res>
    implements _$ModelTypeSupportReadCopyWith<$Res> {
  __$ModelTypeSupportReadCopyWithImpl(this._self, this._then);

  final _ModelTypeSupportRead _self;
  final $Res Function(_ModelTypeSupportRead) _then;

/// Create a copy of ModelTypeSupportRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelType = null,Object? exclusions = null,}) {
  return _then(_ModelTypeSupportRead(
modelType: null == modelType ? _self.modelType : modelType // ignore: cast_nullable_to_non_nullable
as ModelType,exclusions: null == exclusions ? _self.exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of ModelTypeSupportRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get exclusions {

  return $TypedListRefCopyWith<$Res>(_self.exclusions, (value) {
    return _then(_self.copyWith(exclusions: value));
  });
}
}

/// @nodoc
mixin _$ModelTypeExclusionReadItem {

 ModelTypeExclusion get value;
/// Create a copy of ModelTypeExclusionReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelTypeExclusionReadItemCopyWith<ModelTypeExclusionReadItem> get copyWith => _$ModelTypeExclusionReadItemCopyWithImpl<ModelTypeExclusionReadItem>(this as ModelTypeExclusionReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelTypeExclusionReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelTypeExclusionReadItem&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ModelTypeExclusionReadItem;
  return Object.hash(runtimeType,_this.value);
}

@override
String toString() {
  final _this = this as ModelTypeExclusionReadItem;
  return 'ModelTypeExclusionReadItem(value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $ModelTypeExclusionReadItemCopyWith<$Res>  {
  factory $ModelTypeExclusionReadItemCopyWith(ModelTypeExclusionReadItem value, $Res Function(ModelTypeExclusionReadItem) _then) = _$ModelTypeExclusionReadItemCopyWithImpl;
@useResult
$Res call({
 ModelTypeExclusion value
});




}
/// @nodoc
class _$ModelTypeExclusionReadItemCopyWithImpl<$Res>
    implements $ModelTypeExclusionReadItemCopyWith<$Res> {
  _$ModelTypeExclusionReadItemCopyWithImpl(this._self, this._then);

  final ModelTypeExclusionReadItem _self;
  final $Res Function(ModelTypeExclusionReadItem) _then;

/// Create a copy of ModelTypeExclusionReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(ModelTypeExclusionReadItem(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ModelTypeExclusion,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelTypeExclusionReadItem].
extension ModelTypeExclusionReadItemPatterns on ModelTypeExclusionReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelTypeExclusionReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelTypeExclusionReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelTypeExclusionReadItem value)  $default,){
final _that = this;
switch (_that) {
case _ModelTypeExclusionReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelTypeExclusionReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _ModelTypeExclusionReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModelTypeExclusion value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelTypeExclusionReadItem() when $default != null:
return $default(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModelTypeExclusion value)  $default,) {final _that = this;
switch (_that) {
case _ModelTypeExclusionReadItem():
return $default(_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModelTypeExclusion value)?  $default,) {final _that = this;
switch (_that) {
case _ModelTypeExclusionReadItem() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ModelTypeExclusionReadItem implements ModelTypeExclusionReadItem {
  const _ModelTypeExclusionReadItem({required this.value});


@override final  ModelTypeExclusion value;

/// Create a copy of ModelTypeExclusionReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelTypeExclusionReadItemCopyWith<_ModelTypeExclusionReadItem> get copyWith => __$ModelTypeExclusionReadItemCopyWithImpl<_ModelTypeExclusionReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelTypeExclusionReadItem&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'ModelTypeExclusionReadItem(value: $value)';
}


}

/// @nodoc
abstract mixin class _$ModelTypeExclusionReadItemCopyWith<$Res> implements $ModelTypeExclusionReadItemCopyWith<$Res> {
  factory _$ModelTypeExclusionReadItemCopyWith(_ModelTypeExclusionReadItem value, $Res Function(_ModelTypeExclusionReadItem) _then) = __$ModelTypeExclusionReadItemCopyWithImpl;
@override @useResult
$Res call({
 ModelTypeExclusion value
});




}
/// @nodoc
class __$ModelTypeExclusionReadItemCopyWithImpl<$Res>
    implements _$ModelTypeExclusionReadItemCopyWith<$Res> {
  __$ModelTypeExclusionReadItemCopyWithImpl(this._self, this._then);

  final _ModelTypeExclusionReadItem _self;
  final $Res Function(_ModelTypeExclusionReadItem) _then;

/// Create a copy of ModelTypeExclusionReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_ModelTypeExclusionReadItem(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ModelTypeExclusion,
  ));
}


}

/// @nodoc
mixin _$ModelContextResolutionRead {

 ModelContextUnavailable? get unavailable; int? get contextWindow; int? get inputTokenLimit; int? get autoCompactLimit; ModelContextAdjustment? get adjustment;
/// Create a copy of ModelContextResolutionRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelContextResolutionReadCopyWith<ModelContextResolutionRead> get copyWith => _$ModelContextResolutionReadCopyWithImpl<ModelContextResolutionRead>(this as ModelContextResolutionRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelContextResolutionRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelContextResolutionRead&&(identical(other.unavailable, _this.unavailable) || other.unavailable == _this.unavailable)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.inputTokenLimit, _this.inputTokenLimit) || other.inputTokenLimit == _this.inputTokenLimit)&&(identical(other.autoCompactLimit, _this.autoCompactLimit) || other.autoCompactLimit == _this.autoCompactLimit)&&(identical(other.adjustment, _this.adjustment) || other.adjustment == _this.adjustment));
}


@override
int get hashCode {
  final _this = this as ModelContextResolutionRead;
  return Object.hash(runtimeType,_this.unavailable,_this.contextWindow,_this.inputTokenLimit,_this.autoCompactLimit,_this.adjustment);
}

@override
String toString() {
  final _this = this as ModelContextResolutionRead;
  return 'ModelContextResolutionRead(unavailable: ${_this.unavailable}, contextWindow: ${_this.contextWindow}, inputTokenLimit: ${_this.inputTokenLimit}, autoCompactLimit: ${_this.autoCompactLimit}, adjustment: ${_this.adjustment})';
}


}

/// @nodoc
abstract mixin class $ModelContextResolutionReadCopyWith<$Res>  {
  factory $ModelContextResolutionReadCopyWith(ModelContextResolutionRead value, $Res Function(ModelContextResolutionRead) _then) = _$ModelContextResolutionReadCopyWithImpl;
@useResult
$Res call({
 ModelContextUnavailable? unavailable, int? contextWindow, int? inputTokenLimit, int? autoCompactLimit, ModelContextAdjustment? adjustment
});




}
/// @nodoc
class _$ModelContextResolutionReadCopyWithImpl<$Res>
    implements $ModelContextResolutionReadCopyWith<$Res> {
  _$ModelContextResolutionReadCopyWithImpl(this._self, this._then);

  final ModelContextResolutionRead _self;
  final $Res Function(ModelContextResolutionRead) _then;

/// Create a copy of ModelContextResolutionRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? unavailable = freezed,Object? contextWindow = freezed,Object? inputTokenLimit = freezed,Object? autoCompactLimit = freezed,Object? adjustment = freezed,}) {
  return _then(ModelContextResolutionRead(
unavailable: freezed == unavailable ? _self.unavailable : unavailable // ignore: cast_nullable_to_non_nullable
as ModelContextUnavailable?,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,inputTokenLimit: freezed == inputTokenLimit ? _self.inputTokenLimit : inputTokenLimit // ignore: cast_nullable_to_non_nullable
as int?,autoCompactLimit: freezed == autoCompactLimit ? _self.autoCompactLimit : autoCompactLimit // ignore: cast_nullable_to_non_nullable
as int?,adjustment: freezed == adjustment ? _self.adjustment : adjustment // ignore: cast_nullable_to_non_nullable
as ModelContextAdjustment?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelContextResolutionRead].
extension ModelContextResolutionReadPatterns on ModelContextResolutionRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelContextResolutionRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelContextResolutionRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelContextResolutionRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelContextResolutionRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelContextResolutionRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelContextResolutionRead() when $default != null:
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
case _ModelContextResolutionRead() when $default != null:
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
case _ModelContextResolutionRead():
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
case _ModelContextResolutionRead() when $default != null:
return $default(_that.unavailable,_that.contextWindow,_that.inputTokenLimit,_that.autoCompactLimit,_that.adjustment);case _:
  return null;

}
}

}

/// @nodoc


class _ModelContextResolutionRead implements ModelContextResolutionRead {
  const _ModelContextResolutionRead({required this.unavailable, required this.contextWindow, required this.inputTokenLimit, required this.autoCompactLimit, required this.adjustment});


@override final  ModelContextUnavailable? unavailable;
@override final  int? contextWindow;
@override final  int? inputTokenLimit;
@override final  int? autoCompactLimit;
@override final  ModelContextAdjustment? adjustment;

/// Create a copy of ModelContextResolutionRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelContextResolutionReadCopyWith<_ModelContextResolutionRead> get copyWith => __$ModelContextResolutionReadCopyWithImpl<_ModelContextResolutionRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelContextResolutionRead&&(identical(other.unavailable, unavailable) || other.unavailable == unavailable)&&(identical(other.contextWindow, contextWindow) || other.contextWindow == contextWindow)&&(identical(other.inputTokenLimit, inputTokenLimit) || other.inputTokenLimit == inputTokenLimit)&&(identical(other.autoCompactLimit, autoCompactLimit) || other.autoCompactLimit == autoCompactLimit)&&(identical(other.adjustment, adjustment) || other.adjustment == adjustment));
}


@override
int get hashCode {
    return Object.hash(runtimeType,unavailable,contextWindow,inputTokenLimit,autoCompactLimit,adjustment);
}

@override
String toString() {
    return 'ModelContextResolutionRead(unavailable: $unavailable, contextWindow: $contextWindow, inputTokenLimit: $inputTokenLimit, autoCompactLimit: $autoCompactLimit, adjustment: $adjustment)';
}


}

/// @nodoc
abstract mixin class _$ModelContextResolutionReadCopyWith<$Res> implements $ModelContextResolutionReadCopyWith<$Res> {
  factory _$ModelContextResolutionReadCopyWith(_ModelContextResolutionRead value, $Res Function(_ModelContextResolutionRead) _then) = __$ModelContextResolutionReadCopyWithImpl;
@override @useResult
$Res call({
 ModelContextUnavailable? unavailable, int? contextWindow, int? inputTokenLimit, int? autoCompactLimit, ModelContextAdjustment? adjustment
});




}
/// @nodoc
class __$ModelContextResolutionReadCopyWithImpl<$Res>
    implements _$ModelContextResolutionReadCopyWith<$Res> {
  __$ModelContextResolutionReadCopyWithImpl(this._self, this._then);

  final _ModelContextResolutionRead _self;
  final $Res Function(_ModelContextResolutionRead) _then;

/// Create a copy of ModelContextResolutionRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? unavailable = freezed,Object? contextWindow = freezed,Object? inputTokenLimit = freezed,Object? autoCompactLimit = freezed,Object? adjustment = freezed,}) {
  return _then(_ModelContextResolutionRead(
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
mixin _$ModelTransportDescriptorRead {

 ReadText get protocol; TypedListRef get connectionModes; ReadText get defaultConnectionMode;
/// Create a copy of ModelTransportDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelTransportDescriptorReadCopyWith<ModelTransportDescriptorRead> get copyWith => _$ModelTransportDescriptorReadCopyWithImpl<ModelTransportDescriptorRead>(this as ModelTransportDescriptorRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelTransportDescriptorRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelTransportDescriptorRead&&(identical(other.protocol, _this.protocol) || other.protocol == _this.protocol)&&(identical(other.connectionModes, _this.connectionModes) || other.connectionModes == _this.connectionModes)&&(identical(other.defaultConnectionMode, _this.defaultConnectionMode) || other.defaultConnectionMode == _this.defaultConnectionMode));
}


@override
int get hashCode {
  final _this = this as ModelTransportDescriptorRead;
  return Object.hash(runtimeType,_this.protocol,_this.connectionModes,_this.defaultConnectionMode);
}



}

/// @nodoc
abstract mixin class $ModelTransportDescriptorReadCopyWith<$Res>  {
  factory $ModelTransportDescriptorReadCopyWith(ModelTransportDescriptorRead value, $Res Function(ModelTransportDescriptorRead) _then) = _$ModelTransportDescriptorReadCopyWithImpl;
@useResult
$Res call({
 ReadText protocol, TypedListRef connectionModes, ReadText defaultConnectionMode
});


$ReadTextCopyWith<$Res> get protocol;$TypedListRefCopyWith<$Res> get connectionModes;$ReadTextCopyWith<$Res> get defaultConnectionMode;

}
/// @nodoc
class _$ModelTransportDescriptorReadCopyWithImpl<$Res>
    implements $ModelTransportDescriptorReadCopyWith<$Res> {
  _$ModelTransportDescriptorReadCopyWithImpl(this._self, this._then);

  final ModelTransportDescriptorRead _self;
  final $Res Function(ModelTransportDescriptorRead) _then;

/// Create a copy of ModelTransportDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? protocol = null,Object? connectionModes = null,Object? defaultConnectionMode = null,}) {
  return _then(ModelTransportDescriptorRead(
protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as ReadText,connectionModes: null == connectionModes ? _self.connectionModes : connectionModes // ignore: cast_nullable_to_non_nullable
as TypedListRef,defaultConnectionMode: null == defaultConnectionMode ? _self.defaultConnectionMode : defaultConnectionMode // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of ModelTransportDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get protocol {

  return $ReadTextCopyWith<$Res>(_self.protocol, (value) {
    return _then(_self.copyWith(protocol: value));
  });
}/// Create a copy of ModelTransportDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get connectionModes {

  return $TypedListRefCopyWith<$Res>(_self.connectionModes, (value) {
    return _then(_self.copyWith(connectionModes: value));
  });
}/// Create a copy of ModelTransportDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get defaultConnectionMode {

  return $ReadTextCopyWith<$Res>(_self.defaultConnectionMode, (value) {
    return _then(_self.copyWith(defaultConnectionMode: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelTransportDescriptorRead].
extension ModelTransportDescriptorReadPatterns on ModelTransportDescriptorRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelTransportDescriptorRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelTransportDescriptorRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelTransportDescriptorRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelTransportDescriptorRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelTransportDescriptorRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelTransportDescriptorRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText protocol,  TypedListRef connectionModes,  ReadText defaultConnectionMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelTransportDescriptorRead() when $default != null:
return $default(_that.protocol,_that.connectionModes,_that.defaultConnectionMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText protocol,  TypedListRef connectionModes,  ReadText defaultConnectionMode)  $default,) {final _that = this;
switch (_that) {
case _ModelTransportDescriptorRead():
return $default(_that.protocol,_that.connectionModes,_that.defaultConnectionMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText protocol,  TypedListRef connectionModes,  ReadText defaultConnectionMode)?  $default,) {final _that = this;
switch (_that) {
case _ModelTransportDescriptorRead() when $default != null:
return $default(_that.protocol,_that.connectionModes,_that.defaultConnectionMode);case _:
  return null;

}
}

}

/// @nodoc


class _ModelTransportDescriptorRead implements ModelTransportDescriptorRead {
  const _ModelTransportDescriptorRead({required this.protocol, required this.connectionModes, required this.defaultConnectionMode});


@override final  ReadText protocol;
@override final  TypedListRef connectionModes;
@override final  ReadText defaultConnectionMode;

/// Create a copy of ModelTransportDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelTransportDescriptorReadCopyWith<_ModelTransportDescriptorRead> get copyWith => __$ModelTransportDescriptorReadCopyWithImpl<_ModelTransportDescriptorRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelTransportDescriptorRead&&(identical(other.protocol, protocol) || other.protocol == protocol)&&(identical(other.connectionModes, connectionModes) || other.connectionModes == connectionModes)&&(identical(other.defaultConnectionMode, defaultConnectionMode) || other.defaultConnectionMode == defaultConnectionMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,protocol,connectionModes,defaultConnectionMode);
}



}

/// @nodoc
abstract mixin class _$ModelTransportDescriptorReadCopyWith<$Res> implements $ModelTransportDescriptorReadCopyWith<$Res> {
  factory _$ModelTransportDescriptorReadCopyWith(_ModelTransportDescriptorRead value, $Res Function(_ModelTransportDescriptorRead) _then) = __$ModelTransportDescriptorReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText protocol, TypedListRef connectionModes, ReadText defaultConnectionMode
});


@override $ReadTextCopyWith<$Res> get protocol;@override $TypedListRefCopyWith<$Res> get connectionModes;@override $ReadTextCopyWith<$Res> get defaultConnectionMode;

}
/// @nodoc
class __$ModelTransportDescriptorReadCopyWithImpl<$Res>
    implements _$ModelTransportDescriptorReadCopyWith<$Res> {
  __$ModelTransportDescriptorReadCopyWithImpl(this._self, this._then);

  final _ModelTransportDescriptorRead _self;
  final $Res Function(_ModelTransportDescriptorRead) _then;

/// Create a copy of ModelTransportDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? protocol = null,Object? connectionModes = null,Object? defaultConnectionMode = null,}) {
  return _then(_ModelTransportDescriptorRead(
protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as ReadText,connectionModes: null == connectionModes ? _self.connectionModes : connectionModes // ignore: cast_nullable_to_non_nullable
as TypedListRef,defaultConnectionMode: null == defaultConnectionMode ? _self.defaultConnectionMode : defaultConnectionMode // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of ModelTransportDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get protocol {

  return $ReadTextCopyWith<$Res>(_self.protocol, (value) {
    return _then(_self.copyWith(protocol: value));
  });
}/// Create a copy of ModelTransportDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get connectionModes {

  return $TypedListRefCopyWith<$Res>(_self.connectionModes, (value) {
    return _then(_self.copyWith(connectionModes: value));
  });
}/// Create a copy of ModelTransportDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get defaultConnectionMode {

  return $ReadTextCopyWith<$Res>(_self.defaultConnectionMode, (value) {
    return _then(_self.copyWith(defaultConnectionMode: value));
  });
}
}

/// @nodoc
mixin _$ConnectionModeRead {

 ReadText get id; ReadText get displayName;
/// Create a copy of ConnectionModeRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionModeReadCopyWith<ConnectionModeRead> get copyWith => _$ConnectionModeReadCopyWithImpl<ConnectionModeRead>(this as ConnectionModeRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConnectionModeRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionModeRead&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName));
}


@override
int get hashCode {
  final _this = this as ConnectionModeRead;
  return Object.hash(runtimeType,_this.id,_this.displayName);
}



}

/// @nodoc
abstract mixin class $ConnectionModeReadCopyWith<$Res>  {
  factory $ConnectionModeReadCopyWith(ConnectionModeRead value, $Res Function(ConnectionModeRead) _then) = _$ConnectionModeReadCopyWithImpl;
@useResult
$Res call({
 ReadText id, ReadText displayName
});


$ReadTextCopyWith<$Res> get id;$ReadTextCopyWith<$Res> get displayName;

}
/// @nodoc
class _$ConnectionModeReadCopyWithImpl<$Res>
    implements $ConnectionModeReadCopyWith<$Res> {
  _$ConnectionModeReadCopyWithImpl(this._self, this._then);

  final ConnectionModeRead _self;
  final $Res Function(ConnectionModeRead) _then;

/// Create a copy of ConnectionModeRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,}) {
  return _then(ConnectionModeRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of ConnectionModeRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of ConnectionModeRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConnectionModeRead].
extension ConnectionModeReadPatterns on ConnectionModeRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConnectionModeRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConnectionModeRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConnectionModeRead value)  $default,){
final _that = this;
switch (_that) {
case _ConnectionModeRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConnectionModeRead value)?  $default,){
final _that = this;
switch (_that) {
case _ConnectionModeRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText id,  ReadText displayName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConnectionModeRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText id,  ReadText displayName)  $default,) {final _that = this;
switch (_that) {
case _ConnectionModeRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText id,  ReadText displayName)?  $default,) {final _that = this;
switch (_that) {
case _ConnectionModeRead() when $default != null:
return $default(_that.id,_that.displayName);case _:
  return null;

}
}

}

/// @nodoc


class _ConnectionModeRead implements ConnectionModeRead {
  const _ConnectionModeRead({required this.id, required this.displayName});


@override final  ReadText id;
@override final  ReadText displayName;

/// Create a copy of ConnectionModeRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConnectionModeReadCopyWith<_ConnectionModeRead> get copyWith => __$ConnectionModeReadCopyWithImpl<_ConnectionModeRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConnectionModeRead&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName);
}



}

/// @nodoc
abstract mixin class _$ConnectionModeReadCopyWith<$Res> implements $ConnectionModeReadCopyWith<$Res> {
  factory _$ConnectionModeReadCopyWith(_ConnectionModeRead value, $Res Function(_ConnectionModeRead) _then) = __$ConnectionModeReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText id, ReadText displayName
});


@override $ReadTextCopyWith<$Res> get id;@override $ReadTextCopyWith<$Res> get displayName;

}
/// @nodoc
class __$ConnectionModeReadCopyWithImpl<$Res>
    implements _$ConnectionModeReadCopyWith<$Res> {
  __$ConnectionModeReadCopyWithImpl(this._self, this._then);

  final _ConnectionModeRead _self;
  final $Res Function(_ConnectionModeRead) _then;

/// Create a copy of ConnectionModeRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,}) {
  return _then(_ConnectionModeRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of ConnectionModeRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of ConnectionModeRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}
}

/// @nodoc
mixin _$ModelCapabilitiesRead {

 TypedListRef get input; TypedListRef get output; bool get streaming; bool get temperature; bool get reasoning; bool get webSearch; bool get functionCalling; bool get parallelToolCalls; bool get customTools; bool get freeformTools; bool get instructionSnapshotOverrides; ReadText? get nativeContextFamily;
/// Create a copy of ModelCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCapabilitiesReadCopyWith<ModelCapabilitiesRead> get copyWith => _$ModelCapabilitiesReadCopyWithImpl<ModelCapabilitiesRead>(this as ModelCapabilitiesRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelCapabilitiesRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCapabilitiesRead&&(identical(other.input, _this.input) || other.input == _this.input)&&(identical(other.output, _this.output) || other.output == _this.output)&&(identical(other.streaming, _this.streaming) || other.streaming == _this.streaming)&&(identical(other.temperature, _this.temperature) || other.temperature == _this.temperature)&&(identical(other.reasoning, _this.reasoning) || other.reasoning == _this.reasoning)&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.functionCalling, _this.functionCalling) || other.functionCalling == _this.functionCalling)&&(identical(other.parallelToolCalls, _this.parallelToolCalls) || other.parallelToolCalls == _this.parallelToolCalls)&&(identical(other.customTools, _this.customTools) || other.customTools == _this.customTools)&&(identical(other.freeformTools, _this.freeformTools) || other.freeformTools == _this.freeformTools)&&(identical(other.instructionSnapshotOverrides, _this.instructionSnapshotOverrides) || other.instructionSnapshotOverrides == _this.instructionSnapshotOverrides)&&(identical(other.nativeContextFamily, _this.nativeContextFamily) || other.nativeContextFamily == _this.nativeContextFamily));
}


@override
int get hashCode {
  final _this = this as ModelCapabilitiesRead;
  return Object.hash(runtimeType,_this.input,_this.output,_this.streaming,_this.temperature,_this.reasoning,_this.webSearch,_this.functionCalling,_this.parallelToolCalls,_this.customTools,_this.freeformTools,_this.instructionSnapshotOverrides,_this.nativeContextFamily);
}



}

/// @nodoc
abstract mixin class $ModelCapabilitiesReadCopyWith<$Res>  {
  factory $ModelCapabilitiesReadCopyWith(ModelCapabilitiesRead value, $Res Function(ModelCapabilitiesRead) _then) = _$ModelCapabilitiesReadCopyWithImpl;
@useResult
$Res call({
 TypedListRef input, TypedListRef output, bool streaming, bool temperature, bool reasoning, bool webSearch, bool functionCalling, bool parallelToolCalls, bool customTools, bool freeformTools, bool instructionSnapshotOverrides, ReadText? nativeContextFamily
});


$TypedListRefCopyWith<$Res> get input;$TypedListRefCopyWith<$Res> get output;$ReadTextCopyWith<$Res>? get nativeContextFamily;

}
/// @nodoc
class _$ModelCapabilitiesReadCopyWithImpl<$Res>
    implements $ModelCapabilitiesReadCopyWith<$Res> {
  _$ModelCapabilitiesReadCopyWithImpl(this._self, this._then);

  final ModelCapabilitiesRead _self;
  final $Res Function(ModelCapabilitiesRead) _then;

/// Create a copy of ModelCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? input = null,Object? output = null,Object? streaming = null,Object? temperature = null,Object? reasoning = null,Object? webSearch = null,Object? functionCalling = null,Object? parallelToolCalls = null,Object? customTools = null,Object? freeformTools = null,Object? instructionSnapshotOverrides = null,Object? nativeContextFamily = freezed,}) {
  return _then(ModelCapabilitiesRead(
input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as TypedListRef,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as TypedListRef,streaming: null == streaming ? _self.streaming : streaming // ignore: cast_nullable_to_non_nullable
as bool,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as bool,reasoning: null == reasoning ? _self.reasoning : reasoning // ignore: cast_nullable_to_non_nullable
as bool,webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as bool,functionCalling: null == functionCalling ? _self.functionCalling : functionCalling // ignore: cast_nullable_to_non_nullable
as bool,parallelToolCalls: null == parallelToolCalls ? _self.parallelToolCalls : parallelToolCalls // ignore: cast_nullable_to_non_nullable
as bool,customTools: null == customTools ? _self.customTools : customTools // ignore: cast_nullable_to_non_nullable
as bool,freeformTools: null == freeformTools ? _self.freeformTools : freeformTools // ignore: cast_nullable_to_non_nullable
as bool,instructionSnapshotOverrides: null == instructionSnapshotOverrides ? _self.instructionSnapshotOverrides : instructionSnapshotOverrides // ignore: cast_nullable_to_non_nullable
as bool,nativeContextFamily: freezed == nativeContextFamily ? _self.nativeContextFamily : nativeContextFamily // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of ModelCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get input {

  return $TypedListRefCopyWith<$Res>(_self.input, (value) {
    return _then(_self.copyWith(input: value));
  });
}/// Create a copy of ModelCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get output {

  return $TypedListRefCopyWith<$Res>(_self.output, (value) {
    return _then(_self.copyWith(output: value));
  });
}/// Create a copy of ModelCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get nativeContextFamily {
    if (_self.nativeContextFamily == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.nativeContextFamily!, (value) {
    return _then(_self.copyWith(nativeContextFamily: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelCapabilitiesRead].
extension ModelCapabilitiesReadPatterns on ModelCapabilitiesRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelCapabilitiesRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelCapabilitiesRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelCapabilitiesRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelCapabilitiesRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelCapabilitiesRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelCapabilitiesRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef input,  TypedListRef output,  bool streaming,  bool temperature,  bool reasoning,  bool webSearch,  bool functionCalling,  bool parallelToolCalls,  bool customTools,  bool freeformTools,  bool instructionSnapshotOverrides,  ReadText? nativeContextFamily)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelCapabilitiesRead() when $default != null:
return $default(_that.input,_that.output,_that.streaming,_that.temperature,_that.reasoning,_that.webSearch,_that.functionCalling,_that.parallelToolCalls,_that.customTools,_that.freeformTools,_that.instructionSnapshotOverrides,_that.nativeContextFamily);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef input,  TypedListRef output,  bool streaming,  bool temperature,  bool reasoning,  bool webSearch,  bool functionCalling,  bool parallelToolCalls,  bool customTools,  bool freeformTools,  bool instructionSnapshotOverrides,  ReadText? nativeContextFamily)  $default,) {final _that = this;
switch (_that) {
case _ModelCapabilitiesRead():
return $default(_that.input,_that.output,_that.streaming,_that.temperature,_that.reasoning,_that.webSearch,_that.functionCalling,_that.parallelToolCalls,_that.customTools,_that.freeformTools,_that.instructionSnapshotOverrides,_that.nativeContextFamily);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef input,  TypedListRef output,  bool streaming,  bool temperature,  bool reasoning,  bool webSearch,  bool functionCalling,  bool parallelToolCalls,  bool customTools,  bool freeformTools,  bool instructionSnapshotOverrides,  ReadText? nativeContextFamily)?  $default,) {final _that = this;
switch (_that) {
case _ModelCapabilitiesRead() when $default != null:
return $default(_that.input,_that.output,_that.streaming,_that.temperature,_that.reasoning,_that.webSearch,_that.functionCalling,_that.parallelToolCalls,_that.customTools,_that.freeformTools,_that.instructionSnapshotOverrides,_that.nativeContextFamily);case _:
  return null;

}
}

}

/// @nodoc


class _ModelCapabilitiesRead implements ModelCapabilitiesRead {
  const _ModelCapabilitiesRead({required this.input, required this.output, required this.streaming, required this.temperature, required this.reasoning, required this.webSearch, required this.functionCalling, required this.parallelToolCalls, required this.customTools, required this.freeformTools, required this.instructionSnapshotOverrides, required this.nativeContextFamily});


@override final  TypedListRef input;
@override final  TypedListRef output;
@override final  bool streaming;
@override final  bool temperature;
@override final  bool reasoning;
@override final  bool webSearch;
@override final  bool functionCalling;
@override final  bool parallelToolCalls;
@override final  bool customTools;
@override final  bool freeformTools;
@override final  bool instructionSnapshotOverrides;
@override final  ReadText? nativeContextFamily;

/// Create a copy of ModelCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelCapabilitiesReadCopyWith<_ModelCapabilitiesRead> get copyWith => __$ModelCapabilitiesReadCopyWithImpl<_ModelCapabilitiesRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCapabilitiesRead&&(identical(other.input, input) || other.input == input)&&(identical(other.output, output) || other.output == output)&&(identical(other.streaming, streaming) || other.streaming == streaming)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.reasoning, reasoning) || other.reasoning == reasoning)&&(identical(other.webSearch, webSearch) || other.webSearch == webSearch)&&(identical(other.functionCalling, functionCalling) || other.functionCalling == functionCalling)&&(identical(other.parallelToolCalls, parallelToolCalls) || other.parallelToolCalls == parallelToolCalls)&&(identical(other.customTools, customTools) || other.customTools == customTools)&&(identical(other.freeformTools, freeformTools) || other.freeformTools == freeformTools)&&(identical(other.instructionSnapshotOverrides, instructionSnapshotOverrides) || other.instructionSnapshotOverrides == instructionSnapshotOverrides)&&(identical(other.nativeContextFamily, nativeContextFamily) || other.nativeContextFamily == nativeContextFamily));
}


@override
int get hashCode {
    return Object.hash(runtimeType,input,output,streaming,temperature,reasoning,webSearch,functionCalling,parallelToolCalls,customTools,freeformTools,instructionSnapshotOverrides,nativeContextFamily);
}



}

/// @nodoc
abstract mixin class _$ModelCapabilitiesReadCopyWith<$Res> implements $ModelCapabilitiesReadCopyWith<$Res> {
  factory _$ModelCapabilitiesReadCopyWith(_ModelCapabilitiesRead value, $Res Function(_ModelCapabilitiesRead) _then) = __$ModelCapabilitiesReadCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef input, TypedListRef output, bool streaming, bool temperature, bool reasoning, bool webSearch, bool functionCalling, bool parallelToolCalls, bool customTools, bool freeformTools, bool instructionSnapshotOverrides, ReadText? nativeContextFamily
});


@override $TypedListRefCopyWith<$Res> get input;@override $TypedListRefCopyWith<$Res> get output;@override $ReadTextCopyWith<$Res>? get nativeContextFamily;

}
/// @nodoc
class __$ModelCapabilitiesReadCopyWithImpl<$Res>
    implements _$ModelCapabilitiesReadCopyWith<$Res> {
  __$ModelCapabilitiesReadCopyWithImpl(this._self, this._then);

  final _ModelCapabilitiesRead _self;
  final $Res Function(_ModelCapabilitiesRead) _then;

/// Create a copy of ModelCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? input = null,Object? output = null,Object? streaming = null,Object? temperature = null,Object? reasoning = null,Object? webSearch = null,Object? functionCalling = null,Object? parallelToolCalls = null,Object? customTools = null,Object? freeformTools = null,Object? instructionSnapshotOverrides = null,Object? nativeContextFamily = freezed,}) {
  return _then(_ModelCapabilitiesRead(
input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as TypedListRef,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as TypedListRef,streaming: null == streaming ? _self.streaming : streaming // ignore: cast_nullable_to_non_nullable
as bool,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as bool,reasoning: null == reasoning ? _self.reasoning : reasoning // ignore: cast_nullable_to_non_nullable
as bool,webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as bool,functionCalling: null == functionCalling ? _self.functionCalling : functionCalling // ignore: cast_nullable_to_non_nullable
as bool,parallelToolCalls: null == parallelToolCalls ? _self.parallelToolCalls : parallelToolCalls // ignore: cast_nullable_to_non_nullable
as bool,customTools: null == customTools ? _self.customTools : customTools // ignore: cast_nullable_to_non_nullable
as bool,freeformTools: null == freeformTools ? _self.freeformTools : freeformTools // ignore: cast_nullable_to_non_nullable
as bool,instructionSnapshotOverrides: null == instructionSnapshotOverrides ? _self.instructionSnapshotOverrides : instructionSnapshotOverrides // ignore: cast_nullable_to_non_nullable
as bool,nativeContextFamily: freezed == nativeContextFamily ? _self.nativeContextFamily : nativeContextFamily // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of ModelCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get input {

  return $TypedListRefCopyWith<$Res>(_self.input, (value) {
    return _then(_self.copyWith(input: value));
  });
}/// Create a copy of ModelCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get output {

  return $TypedListRefCopyWith<$Res>(_self.output, (value) {
    return _then(_self.copyWith(output: value));
  });
}/// Create a copy of ModelCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get nativeContextFamily {
    if (_self.nativeContextFamily == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.nativeContextFamily!, (value) {
    return _then(_self.copyWith(nativeContextFamily: value));
  });
}
}

/// @nodoc
mixin _$ModelInputCapabilityRead {

 ModelModality get modality; TypedListRef get sources; int? get maxCount; int? get maxBytes; int? get maxTotalBytes; int? get maxWidth; int? get maxHeight; TypedListRef get mediaTypes;
/// Create a copy of ModelInputCapabilityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelInputCapabilityReadCopyWith<ModelInputCapabilityRead> get copyWith => _$ModelInputCapabilityReadCopyWithImpl<ModelInputCapabilityRead>(this as ModelInputCapabilityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelInputCapabilityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelInputCapabilityRead&&(identical(other.modality, _this.modality) || other.modality == _this.modality)&&(identical(other.sources, _this.sources) || other.sources == _this.sources)&&(identical(other.maxCount, _this.maxCount) || other.maxCount == _this.maxCount)&&(identical(other.maxBytes, _this.maxBytes) || other.maxBytes == _this.maxBytes)&&(identical(other.maxTotalBytes, _this.maxTotalBytes) || other.maxTotalBytes == _this.maxTotalBytes)&&(identical(other.maxWidth, _this.maxWidth) || other.maxWidth == _this.maxWidth)&&(identical(other.maxHeight, _this.maxHeight) || other.maxHeight == _this.maxHeight)&&(identical(other.mediaTypes, _this.mediaTypes) || other.mediaTypes == _this.mediaTypes));
}


@override
int get hashCode {
  final _this = this as ModelInputCapabilityRead;
  return Object.hash(runtimeType,_this.modality,_this.sources,_this.maxCount,_this.maxBytes,_this.maxTotalBytes,_this.maxWidth,_this.maxHeight,_this.mediaTypes);
}

@override
String toString() {
  final _this = this as ModelInputCapabilityRead;
  return 'ModelInputCapabilityRead(modality: ${_this.modality}, sources: ${_this.sources}, maxCount: ${_this.maxCount}, maxBytes: ${_this.maxBytes}, maxTotalBytes: ${_this.maxTotalBytes}, maxWidth: ${_this.maxWidth}, maxHeight: ${_this.maxHeight}, mediaTypes: ${_this.mediaTypes})';
}


}

/// @nodoc
abstract mixin class $ModelInputCapabilityReadCopyWith<$Res>  {
  factory $ModelInputCapabilityReadCopyWith(ModelInputCapabilityRead value, $Res Function(ModelInputCapabilityRead) _then) = _$ModelInputCapabilityReadCopyWithImpl;
@useResult
$Res call({
 ModelModality modality, TypedListRef sources, int? maxCount, int? maxBytes, int? maxTotalBytes, int? maxWidth, int? maxHeight, TypedListRef mediaTypes
});


$TypedListRefCopyWith<$Res> get sources;$TypedListRefCopyWith<$Res> get mediaTypes;

}
/// @nodoc
class _$ModelInputCapabilityReadCopyWithImpl<$Res>
    implements $ModelInputCapabilityReadCopyWith<$Res> {
  _$ModelInputCapabilityReadCopyWithImpl(this._self, this._then);

  final ModelInputCapabilityRead _self;
  final $Res Function(ModelInputCapabilityRead) _then;

/// Create a copy of ModelInputCapabilityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modality = null,Object? sources = null,Object? maxCount = freezed,Object? maxBytes = freezed,Object? maxTotalBytes = freezed,Object? maxWidth = freezed,Object? maxHeight = freezed,Object? mediaTypes = null,}) {
  return _then(ModelInputCapabilityRead(
modality: null == modality ? _self.modality : modality // ignore: cast_nullable_to_non_nullable
as ModelModality,sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as TypedListRef,maxCount: freezed == maxCount ? _self.maxCount : maxCount // ignore: cast_nullable_to_non_nullable
as int?,maxBytes: freezed == maxBytes ? _self.maxBytes : maxBytes // ignore: cast_nullable_to_non_nullable
as int?,maxTotalBytes: freezed == maxTotalBytes ? _self.maxTotalBytes : maxTotalBytes // ignore: cast_nullable_to_non_nullable
as int?,maxWidth: freezed == maxWidth ? _self.maxWidth : maxWidth // ignore: cast_nullable_to_non_nullable
as int?,maxHeight: freezed == maxHeight ? _self.maxHeight : maxHeight // ignore: cast_nullable_to_non_nullable
as int?,mediaTypes: null == mediaTypes ? _self.mediaTypes : mediaTypes // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of ModelInputCapabilityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get sources {

  return $TypedListRefCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}/// Create a copy of ModelInputCapabilityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get mediaTypes {

  return $TypedListRefCopyWith<$Res>(_self.mediaTypes, (value) {
    return _then(_self.copyWith(mediaTypes: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelInputCapabilityRead].
extension ModelInputCapabilityReadPatterns on ModelInputCapabilityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelInputCapabilityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelInputCapabilityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelInputCapabilityRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelInputCapabilityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelInputCapabilityRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelInputCapabilityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModelModality modality,  TypedListRef sources,  int? maxCount,  int? maxBytes,  int? maxTotalBytes,  int? maxWidth,  int? maxHeight,  TypedListRef mediaTypes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelInputCapabilityRead() when $default != null:
return $default(_that.modality,_that.sources,_that.maxCount,_that.maxBytes,_that.maxTotalBytes,_that.maxWidth,_that.maxHeight,_that.mediaTypes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModelModality modality,  TypedListRef sources,  int? maxCount,  int? maxBytes,  int? maxTotalBytes,  int? maxWidth,  int? maxHeight,  TypedListRef mediaTypes)  $default,) {final _that = this;
switch (_that) {
case _ModelInputCapabilityRead():
return $default(_that.modality,_that.sources,_that.maxCount,_that.maxBytes,_that.maxTotalBytes,_that.maxWidth,_that.maxHeight,_that.mediaTypes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModelModality modality,  TypedListRef sources,  int? maxCount,  int? maxBytes,  int? maxTotalBytes,  int? maxWidth,  int? maxHeight,  TypedListRef mediaTypes)?  $default,) {final _that = this;
switch (_that) {
case _ModelInputCapabilityRead() when $default != null:
return $default(_that.modality,_that.sources,_that.maxCount,_that.maxBytes,_that.maxTotalBytes,_that.maxWidth,_that.maxHeight,_that.mediaTypes);case _:
  return null;

}
}

}

/// @nodoc


class _ModelInputCapabilityRead implements ModelInputCapabilityRead {
  const _ModelInputCapabilityRead({required this.modality, required this.sources, required this.maxCount, required this.maxBytes, required this.maxTotalBytes, required this.maxWidth, required this.maxHeight, required this.mediaTypes});


@override final  ModelModality modality;
@override final  TypedListRef sources;
@override final  int? maxCount;
@override final  int? maxBytes;
@override final  int? maxTotalBytes;
@override final  int? maxWidth;
@override final  int? maxHeight;
@override final  TypedListRef mediaTypes;

/// Create a copy of ModelInputCapabilityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelInputCapabilityReadCopyWith<_ModelInputCapabilityRead> get copyWith => __$ModelInputCapabilityReadCopyWithImpl<_ModelInputCapabilityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelInputCapabilityRead&&(identical(other.modality, modality) || other.modality == modality)&&(identical(other.sources, sources) || other.sources == sources)&&(identical(other.maxCount, maxCount) || other.maxCount == maxCount)&&(identical(other.maxBytes, maxBytes) || other.maxBytes == maxBytes)&&(identical(other.maxTotalBytes, maxTotalBytes) || other.maxTotalBytes == maxTotalBytes)&&(identical(other.maxWidth, maxWidth) || other.maxWidth == maxWidth)&&(identical(other.maxHeight, maxHeight) || other.maxHeight == maxHeight)&&(identical(other.mediaTypes, mediaTypes) || other.mediaTypes == mediaTypes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modality,sources,maxCount,maxBytes,maxTotalBytes,maxWidth,maxHeight,mediaTypes);
}

@override
String toString() {
    return 'ModelInputCapabilityRead(modality: $modality, sources: $sources, maxCount: $maxCount, maxBytes: $maxBytes, maxTotalBytes: $maxTotalBytes, maxWidth: $maxWidth, maxHeight: $maxHeight, mediaTypes: $mediaTypes)';
}


}

/// @nodoc
abstract mixin class _$ModelInputCapabilityReadCopyWith<$Res> implements $ModelInputCapabilityReadCopyWith<$Res> {
  factory _$ModelInputCapabilityReadCopyWith(_ModelInputCapabilityRead value, $Res Function(_ModelInputCapabilityRead) _then) = __$ModelInputCapabilityReadCopyWithImpl;
@override @useResult
$Res call({
 ModelModality modality, TypedListRef sources, int? maxCount, int? maxBytes, int? maxTotalBytes, int? maxWidth, int? maxHeight, TypedListRef mediaTypes
});


@override $TypedListRefCopyWith<$Res> get sources;@override $TypedListRefCopyWith<$Res> get mediaTypes;

}
/// @nodoc
class __$ModelInputCapabilityReadCopyWithImpl<$Res>
    implements _$ModelInputCapabilityReadCopyWith<$Res> {
  __$ModelInputCapabilityReadCopyWithImpl(this._self, this._then);

  final _ModelInputCapabilityRead _self;
  final $Res Function(_ModelInputCapabilityRead) _then;

/// Create a copy of ModelInputCapabilityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modality = null,Object? sources = null,Object? maxCount = freezed,Object? maxBytes = freezed,Object? maxTotalBytes = freezed,Object? maxWidth = freezed,Object? maxHeight = freezed,Object? mediaTypes = null,}) {
  return _then(_ModelInputCapabilityRead(
modality: null == modality ? _self.modality : modality // ignore: cast_nullable_to_non_nullable
as ModelModality,sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as TypedListRef,maxCount: freezed == maxCount ? _self.maxCount : maxCount // ignore: cast_nullable_to_non_nullable
as int?,maxBytes: freezed == maxBytes ? _self.maxBytes : maxBytes // ignore: cast_nullable_to_non_nullable
as int?,maxTotalBytes: freezed == maxTotalBytes ? _self.maxTotalBytes : maxTotalBytes // ignore: cast_nullable_to_non_nullable
as int?,maxWidth: freezed == maxWidth ? _self.maxWidth : maxWidth // ignore: cast_nullable_to_non_nullable
as int?,maxHeight: freezed == maxHeight ? _self.maxHeight : maxHeight // ignore: cast_nullable_to_non_nullable
as int?,mediaTypes: null == mediaTypes ? _self.mediaTypes : mediaTypes // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of ModelInputCapabilityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get sources {

  return $TypedListRefCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}/// Create a copy of ModelInputCapabilityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get mediaTypes {

  return $TypedListRefCopyWith<$Res>(_self.mediaTypes, (value) {
    return _then(_self.copyWith(mediaTypes: value));
  });
}
}

/// @nodoc
mixin _$ModelInputSourceReadItem {

 ModelInputSource get value;
/// Create a copy of ModelInputSourceReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelInputSourceReadItemCopyWith<ModelInputSourceReadItem> get copyWith => _$ModelInputSourceReadItemCopyWithImpl<ModelInputSourceReadItem>(this as ModelInputSourceReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelInputSourceReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelInputSourceReadItem&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ModelInputSourceReadItem;
  return Object.hash(runtimeType,_this.value);
}

@override
String toString() {
  final _this = this as ModelInputSourceReadItem;
  return 'ModelInputSourceReadItem(value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $ModelInputSourceReadItemCopyWith<$Res>  {
  factory $ModelInputSourceReadItemCopyWith(ModelInputSourceReadItem value, $Res Function(ModelInputSourceReadItem) _then) = _$ModelInputSourceReadItemCopyWithImpl;
@useResult
$Res call({
 ModelInputSource value
});




}
/// @nodoc
class _$ModelInputSourceReadItemCopyWithImpl<$Res>
    implements $ModelInputSourceReadItemCopyWith<$Res> {
  _$ModelInputSourceReadItemCopyWithImpl(this._self, this._then);

  final ModelInputSourceReadItem _self;
  final $Res Function(ModelInputSourceReadItem) _then;

/// Create a copy of ModelInputSourceReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(ModelInputSourceReadItem(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ModelInputSource,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelInputSourceReadItem].
extension ModelInputSourceReadItemPatterns on ModelInputSourceReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelInputSourceReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelInputSourceReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelInputSourceReadItem value)  $default,){
final _that = this;
switch (_that) {
case _ModelInputSourceReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelInputSourceReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _ModelInputSourceReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModelInputSource value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelInputSourceReadItem() when $default != null:
return $default(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModelInputSource value)  $default,) {final _that = this;
switch (_that) {
case _ModelInputSourceReadItem():
return $default(_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModelInputSource value)?  $default,) {final _that = this;
switch (_that) {
case _ModelInputSourceReadItem() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ModelInputSourceReadItem implements ModelInputSourceReadItem {
  const _ModelInputSourceReadItem({required this.value});


@override final  ModelInputSource value;

/// Create a copy of ModelInputSourceReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelInputSourceReadItemCopyWith<_ModelInputSourceReadItem> get copyWith => __$ModelInputSourceReadItemCopyWithImpl<_ModelInputSourceReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelInputSourceReadItem&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'ModelInputSourceReadItem(value: $value)';
}


}

/// @nodoc
abstract mixin class _$ModelInputSourceReadItemCopyWith<$Res> implements $ModelInputSourceReadItemCopyWith<$Res> {
  factory _$ModelInputSourceReadItemCopyWith(_ModelInputSourceReadItem value, $Res Function(_ModelInputSourceReadItem) _then) = __$ModelInputSourceReadItemCopyWithImpl;
@override @useResult
$Res call({
 ModelInputSource value
});




}
/// @nodoc
class __$ModelInputSourceReadItemCopyWithImpl<$Res>
    implements _$ModelInputSourceReadItemCopyWith<$Res> {
  __$ModelInputSourceReadItemCopyWithImpl(this._self, this._then);

  final _ModelInputSourceReadItem _self;
  final $Res Function(_ModelInputSourceReadItem) _then;

/// Create a copy of ModelInputSourceReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_ModelInputSourceReadItem(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ModelInputSource,
  ));
}


}

/// @nodoc
mixin _$ModelModalityReadItem {

 ModelModality get value;
/// Create a copy of ModelModalityReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelModalityReadItemCopyWith<ModelModalityReadItem> get copyWith => _$ModelModalityReadItemCopyWithImpl<ModelModalityReadItem>(this as ModelModalityReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelModalityReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelModalityReadItem&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ModelModalityReadItem;
  return Object.hash(runtimeType,_this.value);
}

@override
String toString() {
  final _this = this as ModelModalityReadItem;
  return 'ModelModalityReadItem(value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $ModelModalityReadItemCopyWith<$Res>  {
  factory $ModelModalityReadItemCopyWith(ModelModalityReadItem value, $Res Function(ModelModalityReadItem) _then) = _$ModelModalityReadItemCopyWithImpl;
@useResult
$Res call({
 ModelModality value
});




}
/// @nodoc
class _$ModelModalityReadItemCopyWithImpl<$Res>
    implements $ModelModalityReadItemCopyWith<$Res> {
  _$ModelModalityReadItemCopyWithImpl(this._self, this._then);

  final ModelModalityReadItem _self;
  final $Res Function(ModelModalityReadItem) _then;

/// Create a copy of ModelModalityReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(ModelModalityReadItem(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ModelModality,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelModalityReadItem].
extension ModelModalityReadItemPatterns on ModelModalityReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelModalityReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelModalityReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelModalityReadItem value)  $default,){
final _that = this;
switch (_that) {
case _ModelModalityReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelModalityReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _ModelModalityReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModelModality value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelModalityReadItem() when $default != null:
return $default(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModelModality value)  $default,) {final _that = this;
switch (_that) {
case _ModelModalityReadItem():
return $default(_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModelModality value)?  $default,) {final _that = this;
switch (_that) {
case _ModelModalityReadItem() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ModelModalityReadItem implements ModelModalityReadItem {
  const _ModelModalityReadItem({required this.value});


@override final  ModelModality value;

/// Create a copy of ModelModalityReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelModalityReadItemCopyWith<_ModelModalityReadItem> get copyWith => __$ModelModalityReadItemCopyWithImpl<_ModelModalityReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelModalityReadItem&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'ModelModalityReadItem(value: $value)';
}


}

/// @nodoc
abstract mixin class _$ModelModalityReadItemCopyWith<$Res> implements $ModelModalityReadItemCopyWith<$Res> {
  factory _$ModelModalityReadItemCopyWith(_ModelModalityReadItem value, $Res Function(_ModelModalityReadItem) _then) = __$ModelModalityReadItemCopyWithImpl;
@override @useResult
$Res call({
 ModelModality value
});




}
/// @nodoc
class __$ModelModalityReadItemCopyWithImpl<$Res>
    implements _$ModelModalityReadItemCopyWith<$Res> {
  __$ModelModalityReadItemCopyWithImpl(this._self, this._then);

  final _ModelModalityReadItem _self;
  final $Res Function(_ModelModalityReadItem) _then;

/// Create a copy of ModelModalityReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_ModelModalityReadItem(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ModelModality,
  ));
}


}

/// @nodoc
mixin _$ModelReasoningDescriptorRead {

 ReadText get parameter; ReadText get label; ReadText? get defaultValue; TypedListRef get candidates;
/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelReasoningDescriptorReadCopyWith<ModelReasoningDescriptorRead> get copyWith => _$ModelReasoningDescriptorReadCopyWithImpl<ModelReasoningDescriptorRead>(this as ModelReasoningDescriptorRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelReasoningDescriptorRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelReasoningDescriptorRead&&(identical(other.parameter, _this.parameter) || other.parameter == _this.parameter)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.defaultValue, _this.defaultValue) || other.defaultValue == _this.defaultValue)&&(identical(other.candidates, _this.candidates) || other.candidates == _this.candidates));
}


@override
int get hashCode {
  final _this = this as ModelReasoningDescriptorRead;
  return Object.hash(runtimeType,_this.parameter,_this.label,_this.defaultValue,_this.candidates);
}



}

/// @nodoc
abstract mixin class $ModelReasoningDescriptorReadCopyWith<$Res>  {
  factory $ModelReasoningDescriptorReadCopyWith(ModelReasoningDescriptorRead value, $Res Function(ModelReasoningDescriptorRead) _then) = _$ModelReasoningDescriptorReadCopyWithImpl;
@useResult
$Res call({
 ReadText parameter, ReadText label, ReadText? defaultValue, TypedListRef candidates
});


$ReadTextCopyWith<$Res> get parameter;$ReadTextCopyWith<$Res> get label;$ReadTextCopyWith<$Res>? get defaultValue;$TypedListRefCopyWith<$Res> get candidates;

}
/// @nodoc
class _$ModelReasoningDescriptorReadCopyWithImpl<$Res>
    implements $ModelReasoningDescriptorReadCopyWith<$Res> {
  _$ModelReasoningDescriptorReadCopyWithImpl(this._self, this._then);

  final ModelReasoningDescriptorRead _self;
  final $Res Function(ModelReasoningDescriptorRead) _then;

/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? parameter = null,Object? label = null,Object? defaultValue = freezed,Object? candidates = null,}) {
  return _then(ModelReasoningDescriptorRead(
parameter: null == parameter ? _self.parameter : parameter // ignore: cast_nullable_to_non_nullable
as ReadText,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as ReadText,defaultValue: freezed == defaultValue ? _self.defaultValue : defaultValue // ignore: cast_nullable_to_non_nullable
as ReadText?,candidates: null == candidates ? _self.candidates : candidates // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get parameter {

  return $ReadTextCopyWith<$Res>(_self.parameter, (value) {
    return _then(_self.copyWith(parameter: value));
  });
}/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get label {

  return $ReadTextCopyWith<$Res>(_self.label, (value) {
    return _then(_self.copyWith(label: value));
  });
}/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get defaultValue {
    if (_self.defaultValue == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.defaultValue!, (value) {
    return _then(_self.copyWith(defaultValue: value));
  });
}/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get candidates {

  return $TypedListRefCopyWith<$Res>(_self.candidates, (value) {
    return _then(_self.copyWith(candidates: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelReasoningDescriptorRead].
extension ModelReasoningDescriptorReadPatterns on ModelReasoningDescriptorRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelReasoningDescriptorRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelReasoningDescriptorRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelReasoningDescriptorRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelReasoningDescriptorRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelReasoningDescriptorRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelReasoningDescriptorRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText parameter,  ReadText label,  ReadText? defaultValue,  TypedListRef candidates)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelReasoningDescriptorRead() when $default != null:
return $default(_that.parameter,_that.label,_that.defaultValue,_that.candidates);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText parameter,  ReadText label,  ReadText? defaultValue,  TypedListRef candidates)  $default,) {final _that = this;
switch (_that) {
case _ModelReasoningDescriptorRead():
return $default(_that.parameter,_that.label,_that.defaultValue,_that.candidates);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText parameter,  ReadText label,  ReadText? defaultValue,  TypedListRef candidates)?  $default,) {final _that = this;
switch (_that) {
case _ModelReasoningDescriptorRead() when $default != null:
return $default(_that.parameter,_that.label,_that.defaultValue,_that.candidates);case _:
  return null;

}
}

}

/// @nodoc


class _ModelReasoningDescriptorRead implements ModelReasoningDescriptorRead {
  const _ModelReasoningDescriptorRead({required this.parameter, required this.label, required this.defaultValue, required this.candidates});


@override final  ReadText parameter;
@override final  ReadText label;
@override final  ReadText? defaultValue;
@override final  TypedListRef candidates;

/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelReasoningDescriptorReadCopyWith<_ModelReasoningDescriptorRead> get copyWith => __$ModelReasoningDescriptorReadCopyWithImpl<_ModelReasoningDescriptorRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelReasoningDescriptorRead&&(identical(other.parameter, parameter) || other.parameter == parameter)&&(identical(other.label, label) || other.label == label)&&(identical(other.defaultValue, defaultValue) || other.defaultValue == defaultValue)&&(identical(other.candidates, candidates) || other.candidates == candidates));
}


@override
int get hashCode {
    return Object.hash(runtimeType,parameter,label,defaultValue,candidates);
}



}

/// @nodoc
abstract mixin class _$ModelReasoningDescriptorReadCopyWith<$Res> implements $ModelReasoningDescriptorReadCopyWith<$Res> {
  factory _$ModelReasoningDescriptorReadCopyWith(_ModelReasoningDescriptorRead value, $Res Function(_ModelReasoningDescriptorRead) _then) = __$ModelReasoningDescriptorReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText parameter, ReadText label, ReadText? defaultValue, TypedListRef candidates
});


@override $ReadTextCopyWith<$Res> get parameter;@override $ReadTextCopyWith<$Res> get label;@override $ReadTextCopyWith<$Res>? get defaultValue;@override $TypedListRefCopyWith<$Res> get candidates;

}
/// @nodoc
class __$ModelReasoningDescriptorReadCopyWithImpl<$Res>
    implements _$ModelReasoningDescriptorReadCopyWith<$Res> {
  __$ModelReasoningDescriptorReadCopyWithImpl(this._self, this._then);

  final _ModelReasoningDescriptorRead _self;
  final $Res Function(_ModelReasoningDescriptorRead) _then;

/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? parameter = null,Object? label = null,Object? defaultValue = freezed,Object? candidates = null,}) {
  return _then(_ModelReasoningDescriptorRead(
parameter: null == parameter ? _self.parameter : parameter // ignore: cast_nullable_to_non_nullable
as ReadText,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as ReadText,defaultValue: freezed == defaultValue ? _self.defaultValue : defaultValue // ignore: cast_nullable_to_non_nullable
as ReadText?,candidates: null == candidates ? _self.candidates : candidates // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get parameter {

  return $ReadTextCopyWith<$Res>(_self.parameter, (value) {
    return _then(_self.copyWith(parameter: value));
  });
}/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get label {

  return $ReadTextCopyWith<$Res>(_self.label, (value) {
    return _then(_self.copyWith(label: value));
  });
}/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get defaultValue {
    if (_self.defaultValue == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.defaultValue!, (value) {
    return _then(_self.copyWith(defaultValue: value));
  });
}/// Create a copy of ModelReasoningDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get candidates {

  return $TypedListRefCopyWith<$Res>(_self.candidates, (value) {
    return _then(_self.copyWith(candidates: value));
  });
}
}

/// @nodoc
mixin _$ModelPricingRead {

 ReadText get currency; TypedListRef get tiers; ReadText get source; int get verifiedAt;
/// Create a copy of ModelPricingRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelPricingReadCopyWith<ModelPricingRead> get copyWith => _$ModelPricingReadCopyWithImpl<ModelPricingRead>(this as ModelPricingRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelPricingRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelPricingRead&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&(identical(other.tiers, _this.tiers) || other.tiers == _this.tiers)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.verifiedAt, _this.verifiedAt) || other.verifiedAt == _this.verifiedAt));
}


@override
int get hashCode {
  final _this = this as ModelPricingRead;
  return Object.hash(runtimeType,_this.currency,_this.tiers,_this.source,_this.verifiedAt);
}



}

/// @nodoc
abstract mixin class $ModelPricingReadCopyWith<$Res>  {
  factory $ModelPricingReadCopyWith(ModelPricingRead value, $Res Function(ModelPricingRead) _then) = _$ModelPricingReadCopyWithImpl;
@useResult
$Res call({
 ReadText currency, TypedListRef tiers, ReadText source, int verifiedAt
});


$ReadTextCopyWith<$Res> get currency;$TypedListRefCopyWith<$Res> get tiers;$ReadTextCopyWith<$Res> get source;

}
/// @nodoc
class _$ModelPricingReadCopyWithImpl<$Res>
    implements $ModelPricingReadCopyWith<$Res> {
  _$ModelPricingReadCopyWithImpl(this._self, this._then);

  final ModelPricingRead _self;
  final $Res Function(ModelPricingRead) _then;

/// Create a copy of ModelPricingRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? currency = null,Object? tiers = null,Object? source = null,Object? verifiedAt = null,}) {
  return _then(ModelPricingRead(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as ReadText,tiers: null == tiers ? _self.tiers : tiers // ignore: cast_nullable_to_non_nullable
as TypedListRef,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ReadText,verifiedAt: null == verifiedAt ? _self.verifiedAt : verifiedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ModelPricingRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currency {

  return $ReadTextCopyWith<$Res>(_self.currency, (value) {
    return _then(_self.copyWith(currency: value));
  });
}/// Create a copy of ModelPricingRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get tiers {

  return $TypedListRefCopyWith<$Res>(_self.tiers, (value) {
    return _then(_self.copyWith(tiers: value));
  });
}/// Create a copy of ModelPricingRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get source {

  return $ReadTextCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelPricingRead].
extension ModelPricingReadPatterns on ModelPricingRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelPricingRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelPricingRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelPricingRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelPricingRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelPricingRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelPricingRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText currency,  TypedListRef tiers,  ReadText source,  int verifiedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelPricingRead() when $default != null:
return $default(_that.currency,_that.tiers,_that.source,_that.verifiedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText currency,  TypedListRef tiers,  ReadText source,  int verifiedAt)  $default,) {final _that = this;
switch (_that) {
case _ModelPricingRead():
return $default(_that.currency,_that.tiers,_that.source,_that.verifiedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText currency,  TypedListRef tiers,  ReadText source,  int verifiedAt)?  $default,) {final _that = this;
switch (_that) {
case _ModelPricingRead() when $default != null:
return $default(_that.currency,_that.tiers,_that.source,_that.verifiedAt);case _:
  return null;

}
}

}

/// @nodoc


class _ModelPricingRead implements ModelPricingRead {
  const _ModelPricingRead({required this.currency, required this.tiers, required this.source, required this.verifiedAt});


@override final  ReadText currency;
@override final  TypedListRef tiers;
@override final  ReadText source;
@override final  int verifiedAt;

/// Create a copy of ModelPricingRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelPricingReadCopyWith<_ModelPricingRead> get copyWith => __$ModelPricingReadCopyWithImpl<_ModelPricingRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelPricingRead&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.tiers, tiers) || other.tiers == tiers)&&(identical(other.source, source) || other.source == source)&&(identical(other.verifiedAt, verifiedAt) || other.verifiedAt == verifiedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,currency,tiers,source,verifiedAt);
}



}

/// @nodoc
abstract mixin class _$ModelPricingReadCopyWith<$Res> implements $ModelPricingReadCopyWith<$Res> {
  factory _$ModelPricingReadCopyWith(_ModelPricingRead value, $Res Function(_ModelPricingRead) _then) = __$ModelPricingReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText currency, TypedListRef tiers, ReadText source, int verifiedAt
});


@override $ReadTextCopyWith<$Res> get currency;@override $TypedListRefCopyWith<$Res> get tiers;@override $ReadTextCopyWith<$Res> get source;

}
/// @nodoc
class __$ModelPricingReadCopyWithImpl<$Res>
    implements _$ModelPricingReadCopyWith<$Res> {
  __$ModelPricingReadCopyWithImpl(this._self, this._then);

  final _ModelPricingRead _self;
  final $Res Function(_ModelPricingRead) _then;

/// Create a copy of ModelPricingRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? currency = null,Object? tiers = null,Object? source = null,Object? verifiedAt = null,}) {
  return _then(_ModelPricingRead(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as ReadText,tiers: null == tiers ? _self.tiers : tiers // ignore: cast_nullable_to_non_nullable
as TypedListRef,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ReadText,verifiedAt: null == verifiedAt ? _self.verifiedAt : verifiedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of ModelPricingRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currency {

  return $ReadTextCopyWith<$Res>(_self.currency, (value) {
    return _then(_self.copyWith(currency: value));
  });
}/// Create a copy of ModelPricingRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get tiers {

  return $TypedListRefCopyWith<$Res>(_self.tiers, (value) {
    return _then(_self.copyWith(tiers: value));
  });
}/// Create a copy of ModelPricingRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get source {

  return $ReadTextCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}

/// @nodoc
mixin _$ModelPriceTierRead {

 ReadText get label; double get inputPerMtok; double get outputPerMtok; double? get cacheReadPerMtok; double? get cacheWritePerMtok;
/// Create a copy of ModelPriceTierRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelPriceTierReadCopyWith<ModelPriceTierRead> get copyWith => _$ModelPriceTierReadCopyWithImpl<ModelPriceTierRead>(this as ModelPriceTierRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelPriceTierRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelPriceTierRead&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.inputPerMtok, _this.inputPerMtok) || other.inputPerMtok == _this.inputPerMtok)&&(identical(other.outputPerMtok, _this.outputPerMtok) || other.outputPerMtok == _this.outputPerMtok)&&(identical(other.cacheReadPerMtok, _this.cacheReadPerMtok) || other.cacheReadPerMtok == _this.cacheReadPerMtok)&&(identical(other.cacheWritePerMtok, _this.cacheWritePerMtok) || other.cacheWritePerMtok == _this.cacheWritePerMtok));
}


@override
int get hashCode {
  final _this = this as ModelPriceTierRead;
  return Object.hash(runtimeType,_this.label,_this.inputPerMtok,_this.outputPerMtok,_this.cacheReadPerMtok,_this.cacheWritePerMtok);
}



}

/// @nodoc
abstract mixin class $ModelPriceTierReadCopyWith<$Res>  {
  factory $ModelPriceTierReadCopyWith(ModelPriceTierRead value, $Res Function(ModelPriceTierRead) _then) = _$ModelPriceTierReadCopyWithImpl;
@useResult
$Res call({
 ReadText label, double inputPerMtok, double outputPerMtok, double? cacheReadPerMtok, double? cacheWritePerMtok
});


$ReadTextCopyWith<$Res> get label;

}
/// @nodoc
class _$ModelPriceTierReadCopyWithImpl<$Res>
    implements $ModelPriceTierReadCopyWith<$Res> {
  _$ModelPriceTierReadCopyWithImpl(this._self, this._then);

  final ModelPriceTierRead _self;
  final $Res Function(ModelPriceTierRead) _then;

/// Create a copy of ModelPriceTierRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? inputPerMtok = null,Object? outputPerMtok = null,Object? cacheReadPerMtok = freezed,Object? cacheWritePerMtok = freezed,}) {
  return _then(ModelPriceTierRead(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as ReadText,inputPerMtok: null == inputPerMtok ? _self.inputPerMtok : inputPerMtok // ignore: cast_nullable_to_non_nullable
as double,outputPerMtok: null == outputPerMtok ? _self.outputPerMtok : outputPerMtok // ignore: cast_nullable_to_non_nullable
as double,cacheReadPerMtok: freezed == cacheReadPerMtok ? _self.cacheReadPerMtok : cacheReadPerMtok // ignore: cast_nullable_to_non_nullable
as double?,cacheWritePerMtok: freezed == cacheWritePerMtok ? _self.cacheWritePerMtok : cacheWritePerMtok // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}
/// Create a copy of ModelPriceTierRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get label {

  return $ReadTextCopyWith<$Res>(_self.label, (value) {
    return _then(_self.copyWith(label: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelPriceTierRead].
extension ModelPriceTierReadPatterns on ModelPriceTierRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelPriceTierRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelPriceTierRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelPriceTierRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelPriceTierRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelPriceTierRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelPriceTierRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText label,  double inputPerMtok,  double outputPerMtok,  double? cacheReadPerMtok,  double? cacheWritePerMtok)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelPriceTierRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText label,  double inputPerMtok,  double outputPerMtok,  double? cacheReadPerMtok,  double? cacheWritePerMtok)  $default,) {final _that = this;
switch (_that) {
case _ModelPriceTierRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText label,  double inputPerMtok,  double outputPerMtok,  double? cacheReadPerMtok,  double? cacheWritePerMtok)?  $default,) {final _that = this;
switch (_that) {
case _ModelPriceTierRead() when $default != null:
return $default(_that.label,_that.inputPerMtok,_that.outputPerMtok,_that.cacheReadPerMtok,_that.cacheWritePerMtok);case _:
  return null;

}
}

}

/// @nodoc


class _ModelPriceTierRead implements ModelPriceTierRead {
  const _ModelPriceTierRead({required this.label, required this.inputPerMtok, required this.outputPerMtok, required this.cacheReadPerMtok, required this.cacheWritePerMtok});


@override final  ReadText label;
@override final  double inputPerMtok;
@override final  double outputPerMtok;
@override final  double? cacheReadPerMtok;
@override final  double? cacheWritePerMtok;

/// Create a copy of ModelPriceTierRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelPriceTierReadCopyWith<_ModelPriceTierRead> get copyWith => __$ModelPriceTierReadCopyWithImpl<_ModelPriceTierRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelPriceTierRead&&(identical(other.label, label) || other.label == label)&&(identical(other.inputPerMtok, inputPerMtok) || other.inputPerMtok == inputPerMtok)&&(identical(other.outputPerMtok, outputPerMtok) || other.outputPerMtok == outputPerMtok)&&(identical(other.cacheReadPerMtok, cacheReadPerMtok) || other.cacheReadPerMtok == cacheReadPerMtok)&&(identical(other.cacheWritePerMtok, cacheWritePerMtok) || other.cacheWritePerMtok == cacheWritePerMtok));
}


@override
int get hashCode {
    return Object.hash(runtimeType,label,inputPerMtok,outputPerMtok,cacheReadPerMtok,cacheWritePerMtok);
}



}

/// @nodoc
abstract mixin class _$ModelPriceTierReadCopyWith<$Res> implements $ModelPriceTierReadCopyWith<$Res> {
  factory _$ModelPriceTierReadCopyWith(_ModelPriceTierRead value, $Res Function(_ModelPriceTierRead) _then) = __$ModelPriceTierReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText label, double inputPerMtok, double outputPerMtok, double? cacheReadPerMtok, double? cacheWritePerMtok
});


@override $ReadTextCopyWith<$Res> get label;

}
/// @nodoc
class __$ModelPriceTierReadCopyWithImpl<$Res>
    implements _$ModelPriceTierReadCopyWith<$Res> {
  __$ModelPriceTierReadCopyWithImpl(this._self, this._then);

  final _ModelPriceTierRead _self;
  final $Res Function(_ModelPriceTierRead) _then;

/// Create a copy of ModelPriceTierRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? inputPerMtok = null,Object? outputPerMtok = null,Object? cacheReadPerMtok = freezed,Object? cacheWritePerMtok = freezed,}) {
  return _then(_ModelPriceTierRead(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as ReadText,inputPerMtok: null == inputPerMtok ? _self.inputPerMtok : inputPerMtok // ignore: cast_nullable_to_non_nullable
as double,outputPerMtok: null == outputPerMtok ? _self.outputPerMtok : outputPerMtok // ignore: cast_nullable_to_non_nullable
as double,cacheReadPerMtok: freezed == cacheReadPerMtok ? _self.cacheReadPerMtok : cacheReadPerMtok // ignore: cast_nullable_to_non_nullable
as double?,cacheWritePerMtok: freezed == cacheWritePerMtok ? _self.cacheWritePerMtok : cacheWritePerMtok // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

/// Create a copy of ModelPriceTierRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get label {

  return $ReadTextCopyWith<$Res>(_self.label, (value) {
    return _then(_self.copyWith(label: value));
  });
}
}

/// @nodoc
mixin _$ModelCatalogStatusRead {

 bool get supported; ModelCatalogSource get source; bool get probing; int? get lastSuccessAt; int? get checkedAt; ModelCatalogError? get error; ModelCatalogCacheWarning? get cacheWarning;
/// Create a copy of ModelCatalogStatusRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogStatusReadCopyWith<ModelCatalogStatusRead> get copyWith => _$ModelCatalogStatusReadCopyWithImpl<ModelCatalogStatusRead>(this as ModelCatalogStatusRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelCatalogStatusRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogStatusRead&&(identical(other.supported, _this.supported) || other.supported == _this.supported)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.probing, _this.probing) || other.probing == _this.probing)&&(identical(other.lastSuccessAt, _this.lastSuccessAt) || other.lastSuccessAt == _this.lastSuccessAt)&&(identical(other.checkedAt, _this.checkedAt) || other.checkedAt == _this.checkedAt)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.cacheWarning, _this.cacheWarning) || other.cacheWarning == _this.cacheWarning));
}


@override
int get hashCode {
  final _this = this as ModelCatalogStatusRead;
  return Object.hash(runtimeType,_this.supported,_this.source,_this.probing,_this.lastSuccessAt,_this.checkedAt,_this.error,_this.cacheWarning);
}

@override
String toString() {
  final _this = this as ModelCatalogStatusRead;
  return 'ModelCatalogStatusRead(supported: ${_this.supported}, source: ${_this.source}, probing: ${_this.probing}, lastSuccessAt: ${_this.lastSuccessAt}, checkedAt: ${_this.checkedAt}, error: ${_this.error}, cacheWarning: ${_this.cacheWarning})';
}


}

/// @nodoc
abstract mixin class $ModelCatalogStatusReadCopyWith<$Res>  {
  factory $ModelCatalogStatusReadCopyWith(ModelCatalogStatusRead value, $Res Function(ModelCatalogStatusRead) _then) = _$ModelCatalogStatusReadCopyWithImpl;
@useResult
$Res call({
 bool supported, ModelCatalogSource source, bool probing, int? lastSuccessAt, int? checkedAt, ModelCatalogError? error, ModelCatalogCacheWarning? cacheWarning
});


$ModelCatalogErrorCopyWith<$Res>? get error;

}
/// @nodoc
class _$ModelCatalogStatusReadCopyWithImpl<$Res>
    implements $ModelCatalogStatusReadCopyWith<$Res> {
  _$ModelCatalogStatusReadCopyWithImpl(this._self, this._then);

  final ModelCatalogStatusRead _self;
  final $Res Function(ModelCatalogStatusRead) _then;

/// Create a copy of ModelCatalogStatusRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? supported = null,Object? source = null,Object? probing = null,Object? lastSuccessAt = freezed,Object? checkedAt = freezed,Object? error = freezed,Object? cacheWarning = freezed,}) {
  return _then(ModelCatalogStatusRead(
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
/// Create a copy of ModelCatalogStatusRead
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


/// Adds pattern-matching-related methods to [ModelCatalogStatusRead].
extension ModelCatalogStatusReadPatterns on ModelCatalogStatusRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelCatalogStatusRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelCatalogStatusRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelCatalogStatusRead value)  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogStatusRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelCatalogStatusRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogStatusRead() when $default != null:
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
case _ModelCatalogStatusRead() when $default != null:
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
case _ModelCatalogStatusRead():
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
case _ModelCatalogStatusRead() when $default != null:
return $default(_that.supported,_that.source,_that.probing,_that.lastSuccessAt,_that.checkedAt,_that.error,_that.cacheWarning);case _:
  return null;

}
}

}

/// @nodoc


class _ModelCatalogStatusRead implements ModelCatalogStatusRead {
  const _ModelCatalogStatusRead({required this.supported, required this.source, required this.probing, required this.lastSuccessAt, required this.checkedAt, required this.error, required this.cacheWarning});


@override final  bool supported;
@override final  ModelCatalogSource source;
@override final  bool probing;
@override final  int? lastSuccessAt;
@override final  int? checkedAt;
@override final  ModelCatalogError? error;
@override final  ModelCatalogCacheWarning? cacheWarning;

/// Create a copy of ModelCatalogStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelCatalogStatusReadCopyWith<_ModelCatalogStatusRead> get copyWith => __$ModelCatalogStatusReadCopyWithImpl<_ModelCatalogStatusRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCatalogStatusRead&&(identical(other.supported, supported) || other.supported == supported)&&(identical(other.source, source) || other.source == source)&&(identical(other.probing, probing) || other.probing == probing)&&(identical(other.lastSuccessAt, lastSuccessAt) || other.lastSuccessAt == lastSuccessAt)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.error, error) || other.error == error)&&(identical(other.cacheWarning, cacheWarning) || other.cacheWarning == cacheWarning));
}


@override
int get hashCode {
    return Object.hash(runtimeType,supported,source,probing,lastSuccessAt,checkedAt,error,cacheWarning);
}

@override
String toString() {
    return 'ModelCatalogStatusRead(supported: $supported, source: $source, probing: $probing, lastSuccessAt: $lastSuccessAt, checkedAt: $checkedAt, error: $error, cacheWarning: $cacheWarning)';
}


}

/// @nodoc
abstract mixin class _$ModelCatalogStatusReadCopyWith<$Res> implements $ModelCatalogStatusReadCopyWith<$Res> {
  factory _$ModelCatalogStatusReadCopyWith(_ModelCatalogStatusRead value, $Res Function(_ModelCatalogStatusRead) _then) = __$ModelCatalogStatusReadCopyWithImpl;
@override @useResult
$Res call({
 bool supported, ModelCatalogSource source, bool probing, int? lastSuccessAt, int? checkedAt, ModelCatalogError? error, ModelCatalogCacheWarning? cacheWarning
});


@override $ModelCatalogErrorCopyWith<$Res>? get error;

}
/// @nodoc
class __$ModelCatalogStatusReadCopyWithImpl<$Res>
    implements _$ModelCatalogStatusReadCopyWith<$Res> {
  __$ModelCatalogStatusReadCopyWithImpl(this._self, this._then);

  final _ModelCatalogStatusRead _self;
  final $Res Function(_ModelCatalogStatusRead) _then;

/// Create a copy of ModelCatalogStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? supported = null,Object? source = null,Object? probing = null,Object? lastSuccessAt = freezed,Object? checkedAt = freezed,Object? error = freezed,Object? cacheWarning = freezed,}) {
  return _then(_ModelCatalogStatusRead(
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

/// Create a copy of ModelCatalogStatusRead
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
mixin _$AccountCatalogEntryRead {

 ReadText get accountId; bool get credentialRequired; ReadText get capabilitySource; bool get hostedWebSearch; ReadText get hostedWebSearchDialect; ReadText? get standaloneWebSearch; ReadText get promptCacheDialect; bool get responsesProgrammaticToolCalling; ReadText get defaultModelId; TypedListRef get effectiveModels; ModelCatalogStatusRead get modelCatalog;
/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountCatalogEntryReadCopyWith<AccountCatalogEntryRead> get copyWith => _$AccountCatalogEntryReadCopyWithImpl<AccountCatalogEntryRead>(this as AccountCatalogEntryRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountCatalogEntryRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountCatalogEntryRead&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.credentialRequired, _this.credentialRequired) || other.credentialRequired == _this.credentialRequired)&&(identical(other.capabilitySource, _this.capabilitySource) || other.capabilitySource == _this.capabilitySource)&&(identical(other.hostedWebSearch, _this.hostedWebSearch) || other.hostedWebSearch == _this.hostedWebSearch)&&(identical(other.hostedWebSearchDialect, _this.hostedWebSearchDialect) || other.hostedWebSearchDialect == _this.hostedWebSearchDialect)&&(identical(other.standaloneWebSearch, _this.standaloneWebSearch) || other.standaloneWebSearch == _this.standaloneWebSearch)&&(identical(other.promptCacheDialect, _this.promptCacheDialect) || other.promptCacheDialect == _this.promptCacheDialect)&&(identical(other.responsesProgrammaticToolCalling, _this.responsesProgrammaticToolCalling) || other.responsesProgrammaticToolCalling == _this.responsesProgrammaticToolCalling)&&(identical(other.defaultModelId, _this.defaultModelId) || other.defaultModelId == _this.defaultModelId)&&(identical(other.effectiveModels, _this.effectiveModels) || other.effectiveModels == _this.effectiveModels)&&(identical(other.modelCatalog, _this.modelCatalog) || other.modelCatalog == _this.modelCatalog));
}


@override
int get hashCode {
  final _this = this as AccountCatalogEntryRead;
  return Object.hash(runtimeType,_this.accountId,_this.credentialRequired,_this.capabilitySource,_this.hostedWebSearch,_this.hostedWebSearchDialect,_this.standaloneWebSearch,_this.promptCacheDialect,_this.responsesProgrammaticToolCalling,_this.defaultModelId,_this.effectiveModels,_this.modelCatalog);
}



}

/// @nodoc
abstract mixin class $AccountCatalogEntryReadCopyWith<$Res>  {
  factory $AccountCatalogEntryReadCopyWith(AccountCatalogEntryRead value, $Res Function(AccountCatalogEntryRead) _then) = _$AccountCatalogEntryReadCopyWithImpl;
@useResult
$Res call({
 ReadText accountId, bool credentialRequired, ReadText capabilitySource, bool hostedWebSearch, ReadText hostedWebSearchDialect, ReadText? standaloneWebSearch, ReadText promptCacheDialect, bool responsesProgrammaticToolCalling, ReadText defaultModelId, TypedListRef effectiveModels, ModelCatalogStatusRead modelCatalog
});


$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res> get capabilitySource;$ReadTextCopyWith<$Res> get hostedWebSearchDialect;$ReadTextCopyWith<$Res>? get standaloneWebSearch;$ReadTextCopyWith<$Res> get promptCacheDialect;$ReadTextCopyWith<$Res> get defaultModelId;$TypedListRefCopyWith<$Res> get effectiveModels;$ModelCatalogStatusReadCopyWith<$Res> get modelCatalog;

}
/// @nodoc
class _$AccountCatalogEntryReadCopyWithImpl<$Res>
    implements $AccountCatalogEntryReadCopyWith<$Res> {
  _$AccountCatalogEntryReadCopyWithImpl(this._self, this._then);

  final AccountCatalogEntryRead _self;
  final $Res Function(AccountCatalogEntryRead) _then;

/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? credentialRequired = null,Object? capabilitySource = null,Object? hostedWebSearch = null,Object? hostedWebSearchDialect = null,Object? standaloneWebSearch = freezed,Object? promptCacheDialect = null,Object? responsesProgrammaticToolCalling = null,Object? defaultModelId = null,Object? effectiveModels = null,Object? modelCatalog = null,}) {
  return _then(AccountCatalogEntryRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,credentialRequired: null == credentialRequired ? _self.credentialRequired : credentialRequired // ignore: cast_nullable_to_non_nullable
as bool,capabilitySource: null == capabilitySource ? _self.capabilitySource : capabilitySource // ignore: cast_nullable_to_non_nullable
as ReadText,hostedWebSearch: null == hostedWebSearch ? _self.hostedWebSearch : hostedWebSearch // ignore: cast_nullable_to_non_nullable
as bool,hostedWebSearchDialect: null == hostedWebSearchDialect ? _self.hostedWebSearchDialect : hostedWebSearchDialect // ignore: cast_nullable_to_non_nullable
as ReadText,standaloneWebSearch: freezed == standaloneWebSearch ? _self.standaloneWebSearch : standaloneWebSearch // ignore: cast_nullable_to_non_nullable
as ReadText?,promptCacheDialect: null == promptCacheDialect ? _self.promptCacheDialect : promptCacheDialect // ignore: cast_nullable_to_non_nullable
as ReadText,responsesProgrammaticToolCalling: null == responsesProgrammaticToolCalling ? _self.responsesProgrammaticToolCalling : responsesProgrammaticToolCalling // ignore: cast_nullable_to_non_nullable
as bool,defaultModelId: null == defaultModelId ? _self.defaultModelId : defaultModelId // ignore: cast_nullable_to_non_nullable
as ReadText,effectiveModels: null == effectiveModels ? _self.effectiveModels : effectiveModels // ignore: cast_nullable_to_non_nullable
as TypedListRef,modelCatalog: null == modelCatalog ? _self.modelCatalog : modelCatalog // ignore: cast_nullable_to_non_nullable
as ModelCatalogStatusRead,
  ));
}
/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get capabilitySource {

  return $ReadTextCopyWith<$Res>(_self.capabilitySource, (value) {
    return _then(_self.copyWith(capabilitySource: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get hostedWebSearchDialect {

  return $ReadTextCopyWith<$Res>(_self.hostedWebSearchDialect, (value) {
    return _then(_self.copyWith(hostedWebSearchDialect: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get standaloneWebSearch {
    if (_self.standaloneWebSearch == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.standaloneWebSearch!, (value) {
    return _then(_self.copyWith(standaloneWebSearch: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get promptCacheDialect {

  return $ReadTextCopyWith<$Res>(_self.promptCacheDialect, (value) {
    return _then(_self.copyWith(promptCacheDialect: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get defaultModelId {

  return $ReadTextCopyWith<$Res>(_self.defaultModelId, (value) {
    return _then(_self.copyWith(defaultModelId: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get effectiveModels {

  return $TypedListRefCopyWith<$Res>(_self.effectiveModels, (value) {
    return _then(_self.copyWith(effectiveModels: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogStatusReadCopyWith<$Res> get modelCatalog {

  return $ModelCatalogStatusReadCopyWith<$Res>(_self.modelCatalog, (value) {
    return _then(_self.copyWith(modelCatalog: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountCatalogEntryRead].
extension AccountCatalogEntryReadPatterns on AccountCatalogEntryRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountCatalogEntryRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountCatalogEntryRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountCatalogEntryRead value)  $default,){
final _that = this;
switch (_that) {
case _AccountCatalogEntryRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountCatalogEntryRead value)?  $default,){
final _that = this;
switch (_that) {
case _AccountCatalogEntryRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText accountId,  bool credentialRequired,  ReadText capabilitySource,  bool hostedWebSearch,  ReadText hostedWebSearchDialect,  ReadText? standaloneWebSearch,  ReadText promptCacheDialect,  bool responsesProgrammaticToolCalling,  ReadText defaultModelId,  TypedListRef effectiveModels,  ModelCatalogStatusRead modelCatalog)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountCatalogEntryRead() when $default != null:
return $default(_that.accountId,_that.credentialRequired,_that.capabilitySource,_that.hostedWebSearch,_that.hostedWebSearchDialect,_that.standaloneWebSearch,_that.promptCacheDialect,_that.responsesProgrammaticToolCalling,_that.defaultModelId,_that.effectiveModels,_that.modelCatalog);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText accountId,  bool credentialRequired,  ReadText capabilitySource,  bool hostedWebSearch,  ReadText hostedWebSearchDialect,  ReadText? standaloneWebSearch,  ReadText promptCacheDialect,  bool responsesProgrammaticToolCalling,  ReadText defaultModelId,  TypedListRef effectiveModels,  ModelCatalogStatusRead modelCatalog)  $default,) {final _that = this;
switch (_that) {
case _AccountCatalogEntryRead():
return $default(_that.accountId,_that.credentialRequired,_that.capabilitySource,_that.hostedWebSearch,_that.hostedWebSearchDialect,_that.standaloneWebSearch,_that.promptCacheDialect,_that.responsesProgrammaticToolCalling,_that.defaultModelId,_that.effectiveModels,_that.modelCatalog);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText accountId,  bool credentialRequired,  ReadText capabilitySource,  bool hostedWebSearch,  ReadText hostedWebSearchDialect,  ReadText? standaloneWebSearch,  ReadText promptCacheDialect,  bool responsesProgrammaticToolCalling,  ReadText defaultModelId,  TypedListRef effectiveModels,  ModelCatalogStatusRead modelCatalog)?  $default,) {final _that = this;
switch (_that) {
case _AccountCatalogEntryRead() when $default != null:
return $default(_that.accountId,_that.credentialRequired,_that.capabilitySource,_that.hostedWebSearch,_that.hostedWebSearchDialect,_that.standaloneWebSearch,_that.promptCacheDialect,_that.responsesProgrammaticToolCalling,_that.defaultModelId,_that.effectiveModels,_that.modelCatalog);case _:
  return null;

}
}

}

/// @nodoc


class _AccountCatalogEntryRead implements AccountCatalogEntryRead {
  const _AccountCatalogEntryRead({required this.accountId, required this.credentialRequired, required this.capabilitySource, required this.hostedWebSearch, required this.hostedWebSearchDialect, required this.standaloneWebSearch, required this.promptCacheDialect, required this.responsesProgrammaticToolCalling, required this.defaultModelId, required this.effectiveModels, required this.modelCatalog});


@override final  ReadText accountId;
@override final  bool credentialRequired;
@override final  ReadText capabilitySource;
@override final  bool hostedWebSearch;
@override final  ReadText hostedWebSearchDialect;
@override final  ReadText? standaloneWebSearch;
@override final  ReadText promptCacheDialect;
@override final  bool responsesProgrammaticToolCalling;
@override final  ReadText defaultModelId;
@override final  TypedListRef effectiveModels;
@override final  ModelCatalogStatusRead modelCatalog;

/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountCatalogEntryReadCopyWith<_AccountCatalogEntryRead> get copyWith => __$AccountCatalogEntryReadCopyWithImpl<_AccountCatalogEntryRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountCatalogEntryRead&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.credentialRequired, credentialRequired) || other.credentialRequired == credentialRequired)&&(identical(other.capabilitySource, capabilitySource) || other.capabilitySource == capabilitySource)&&(identical(other.hostedWebSearch, hostedWebSearch) || other.hostedWebSearch == hostedWebSearch)&&(identical(other.hostedWebSearchDialect, hostedWebSearchDialect) || other.hostedWebSearchDialect == hostedWebSearchDialect)&&(identical(other.standaloneWebSearch, standaloneWebSearch) || other.standaloneWebSearch == standaloneWebSearch)&&(identical(other.promptCacheDialect, promptCacheDialect) || other.promptCacheDialect == promptCacheDialect)&&(identical(other.responsesProgrammaticToolCalling, responsesProgrammaticToolCalling) || other.responsesProgrammaticToolCalling == responsesProgrammaticToolCalling)&&(identical(other.defaultModelId, defaultModelId) || other.defaultModelId == defaultModelId)&&(identical(other.effectiveModels, effectiveModels) || other.effectiveModels == effectiveModels)&&(identical(other.modelCatalog, modelCatalog) || other.modelCatalog == modelCatalog));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,credentialRequired,capabilitySource,hostedWebSearch,hostedWebSearchDialect,standaloneWebSearch,promptCacheDialect,responsesProgrammaticToolCalling,defaultModelId,effectiveModels,modelCatalog);
}



}

/// @nodoc
abstract mixin class _$AccountCatalogEntryReadCopyWith<$Res> implements $AccountCatalogEntryReadCopyWith<$Res> {
  factory _$AccountCatalogEntryReadCopyWith(_AccountCatalogEntryRead value, $Res Function(_AccountCatalogEntryRead) _then) = __$AccountCatalogEntryReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText accountId, bool credentialRequired, ReadText capabilitySource, bool hostedWebSearch, ReadText hostedWebSearchDialect, ReadText? standaloneWebSearch, ReadText promptCacheDialect, bool responsesProgrammaticToolCalling, ReadText defaultModelId, TypedListRef effectiveModels, ModelCatalogStatusRead modelCatalog
});


@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res> get capabilitySource;@override $ReadTextCopyWith<$Res> get hostedWebSearchDialect;@override $ReadTextCopyWith<$Res>? get standaloneWebSearch;@override $ReadTextCopyWith<$Res> get promptCacheDialect;@override $ReadTextCopyWith<$Res> get defaultModelId;@override $TypedListRefCopyWith<$Res> get effectiveModels;@override $ModelCatalogStatusReadCopyWith<$Res> get modelCatalog;

}
/// @nodoc
class __$AccountCatalogEntryReadCopyWithImpl<$Res>
    implements _$AccountCatalogEntryReadCopyWith<$Res> {
  __$AccountCatalogEntryReadCopyWithImpl(this._self, this._then);

  final _AccountCatalogEntryRead _self;
  final $Res Function(_AccountCatalogEntryRead) _then;

/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? credentialRequired = null,Object? capabilitySource = null,Object? hostedWebSearch = null,Object? hostedWebSearchDialect = null,Object? standaloneWebSearch = freezed,Object? promptCacheDialect = null,Object? responsesProgrammaticToolCalling = null,Object? defaultModelId = null,Object? effectiveModels = null,Object? modelCatalog = null,}) {
  return _then(_AccountCatalogEntryRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,credentialRequired: null == credentialRequired ? _self.credentialRequired : credentialRequired // ignore: cast_nullable_to_non_nullable
as bool,capabilitySource: null == capabilitySource ? _self.capabilitySource : capabilitySource // ignore: cast_nullable_to_non_nullable
as ReadText,hostedWebSearch: null == hostedWebSearch ? _self.hostedWebSearch : hostedWebSearch // ignore: cast_nullable_to_non_nullable
as bool,hostedWebSearchDialect: null == hostedWebSearchDialect ? _self.hostedWebSearchDialect : hostedWebSearchDialect // ignore: cast_nullable_to_non_nullable
as ReadText,standaloneWebSearch: freezed == standaloneWebSearch ? _self.standaloneWebSearch : standaloneWebSearch // ignore: cast_nullable_to_non_nullable
as ReadText?,promptCacheDialect: null == promptCacheDialect ? _self.promptCacheDialect : promptCacheDialect // ignore: cast_nullable_to_non_nullable
as ReadText,responsesProgrammaticToolCalling: null == responsesProgrammaticToolCalling ? _self.responsesProgrammaticToolCalling : responsesProgrammaticToolCalling // ignore: cast_nullable_to_non_nullable
as bool,defaultModelId: null == defaultModelId ? _self.defaultModelId : defaultModelId // ignore: cast_nullable_to_non_nullable
as ReadText,effectiveModels: null == effectiveModels ? _self.effectiveModels : effectiveModels // ignore: cast_nullable_to_non_nullable
as TypedListRef,modelCatalog: null == modelCatalog ? _self.modelCatalog : modelCatalog // ignore: cast_nullable_to_non_nullable
as ModelCatalogStatusRead,
  ));
}

/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get capabilitySource {

  return $ReadTextCopyWith<$Res>(_self.capabilitySource, (value) {
    return _then(_self.copyWith(capabilitySource: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get hostedWebSearchDialect {

  return $ReadTextCopyWith<$Res>(_self.hostedWebSearchDialect, (value) {
    return _then(_self.copyWith(hostedWebSearchDialect: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get standaloneWebSearch {
    if (_self.standaloneWebSearch == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.standaloneWebSearch!, (value) {
    return _then(_self.copyWith(standaloneWebSearch: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get promptCacheDialect {

  return $ReadTextCopyWith<$Res>(_self.promptCacheDialect, (value) {
    return _then(_self.copyWith(promptCacheDialect: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get defaultModelId {

  return $ReadTextCopyWith<$Res>(_self.defaultModelId, (value) {
    return _then(_self.copyWith(defaultModelId: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get effectiveModels {

  return $TypedListRefCopyWith<$Res>(_self.effectiveModels, (value) {
    return _then(_self.copyWith(effectiveModels: value));
  });
}/// Create a copy of AccountCatalogEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogStatusReadCopyWith<$Res> get modelCatalog {

  return $ModelCatalogStatusReadCopyWith<$Res>(_self.modelCatalog, (value) {
    return _then(_self.copyWith(modelCatalog: value));
  });
}
}

/// @nodoc
mixin _$EffectiveWebSearchRead {

 ReadText get effectiveMode; ReadText get availability; ReadText? get accountId; ReadText? get modelId;
/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EffectiveWebSearchReadCopyWith<EffectiveWebSearchRead> get copyWith => _$EffectiveWebSearchReadCopyWithImpl<EffectiveWebSearchRead>(this as EffectiveWebSearchRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as EffectiveWebSearchRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EffectiveWebSearchRead&&(identical(other.effectiveMode, _this.effectiveMode) || other.effectiveMode == _this.effectiveMode)&&(identical(other.availability, _this.availability) || other.availability == _this.availability)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId));
}


@override
int get hashCode {
  final _this = this as EffectiveWebSearchRead;
  return Object.hash(runtimeType,_this.effectiveMode,_this.availability,_this.accountId,_this.modelId);
}



}

/// @nodoc
abstract mixin class $EffectiveWebSearchReadCopyWith<$Res>  {
  factory $EffectiveWebSearchReadCopyWith(EffectiveWebSearchRead value, $Res Function(EffectiveWebSearchRead) _then) = _$EffectiveWebSearchReadCopyWithImpl;
@useResult
$Res call({
 ReadText effectiveMode, ReadText availability, ReadText? accountId, ReadText? modelId
});


$ReadTextCopyWith<$Res> get effectiveMode;$ReadTextCopyWith<$Res> get availability;$ReadTextCopyWith<$Res>? get accountId;$ReadTextCopyWith<$Res>? get modelId;

}
/// @nodoc
class _$EffectiveWebSearchReadCopyWithImpl<$Res>
    implements $EffectiveWebSearchReadCopyWith<$Res> {
  _$EffectiveWebSearchReadCopyWithImpl(this._self, this._then);

  final EffectiveWebSearchRead _self;
  final $Res Function(EffectiveWebSearchRead) _then;

/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? effectiveMode = null,Object? availability = null,Object? accountId = freezed,Object? modelId = freezed,}) {
  return _then(EffectiveWebSearchRead(
effectiveMode: null == effectiveMode ? _self.effectiveMode : effectiveMode // ignore: cast_nullable_to_non_nullable
as ReadText,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText?,modelId: freezed == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get effectiveMode {

  return $ReadTextCopyWith<$Res>(_self.effectiveMode, (value) {
    return _then(_self.copyWith(effectiveMode: value));
  });
}/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get availability {

  return $ReadTextCopyWith<$Res>(_self.availability, (value) {
    return _then(_self.copyWith(availability: value));
  });
}/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get accountId {
    if (_self.accountId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.accountId!, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get modelId {
    if (_self.modelId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.modelId!, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}
}


/// Adds pattern-matching-related methods to [EffectiveWebSearchRead].
extension EffectiveWebSearchReadPatterns on EffectiveWebSearchRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EffectiveWebSearchRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EffectiveWebSearchRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EffectiveWebSearchRead value)  $default,){
final _that = this;
switch (_that) {
case _EffectiveWebSearchRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EffectiveWebSearchRead value)?  $default,){
final _that = this;
switch (_that) {
case _EffectiveWebSearchRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText effectiveMode,  ReadText availability,  ReadText? accountId,  ReadText? modelId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EffectiveWebSearchRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText effectiveMode,  ReadText availability,  ReadText? accountId,  ReadText? modelId)  $default,) {final _that = this;
switch (_that) {
case _EffectiveWebSearchRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText effectiveMode,  ReadText availability,  ReadText? accountId,  ReadText? modelId)?  $default,) {final _that = this;
switch (_that) {
case _EffectiveWebSearchRead() when $default != null:
return $default(_that.effectiveMode,_that.availability,_that.accountId,_that.modelId);case _:
  return null;

}
}

}

/// @nodoc


class _EffectiveWebSearchRead implements EffectiveWebSearchRead {
  const _EffectiveWebSearchRead({required this.effectiveMode, required this.availability, required this.accountId, required this.modelId});


@override final  ReadText effectiveMode;
@override final  ReadText availability;
@override final  ReadText? accountId;
@override final  ReadText? modelId;

/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EffectiveWebSearchReadCopyWith<_EffectiveWebSearchRead> get copyWith => __$EffectiveWebSearchReadCopyWithImpl<_EffectiveWebSearchRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _EffectiveWebSearchRead&&(identical(other.effectiveMode, effectiveMode) || other.effectiveMode == effectiveMode)&&(identical(other.availability, availability) || other.availability == availability)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,effectiveMode,availability,accountId,modelId);
}



}

/// @nodoc
abstract mixin class _$EffectiveWebSearchReadCopyWith<$Res> implements $EffectiveWebSearchReadCopyWith<$Res> {
  factory _$EffectiveWebSearchReadCopyWith(_EffectiveWebSearchRead value, $Res Function(_EffectiveWebSearchRead) _then) = __$EffectiveWebSearchReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText effectiveMode, ReadText availability, ReadText? accountId, ReadText? modelId
});


@override $ReadTextCopyWith<$Res> get effectiveMode;@override $ReadTextCopyWith<$Res> get availability;@override $ReadTextCopyWith<$Res>? get accountId;@override $ReadTextCopyWith<$Res>? get modelId;

}
/// @nodoc
class __$EffectiveWebSearchReadCopyWithImpl<$Res>
    implements _$EffectiveWebSearchReadCopyWith<$Res> {
  __$EffectiveWebSearchReadCopyWithImpl(this._self, this._then);

  final _EffectiveWebSearchRead _self;
  final $Res Function(_EffectiveWebSearchRead) _then;

/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? effectiveMode = null,Object? availability = null,Object? accountId = freezed,Object? modelId = freezed,}) {
  return _then(_EffectiveWebSearchRead(
effectiveMode: null == effectiveMode ? _self.effectiveMode : effectiveMode // ignore: cast_nullable_to_non_nullable
as ReadText,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText?,modelId: freezed == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get effectiveMode {

  return $ReadTextCopyWith<$Res>(_self.effectiveMode, (value) {
    return _then(_self.copyWith(effectiveMode: value));
  });
}/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get availability {

  return $ReadTextCopyWith<$Res>(_self.availability, (value) {
    return _then(_self.copyWith(availability: value));
  });
}/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get accountId {
    if (_self.accountId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.accountId!, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of EffectiveWebSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get modelId {
    if (_self.modelId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.modelId!, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}
}

/// @nodoc
mixin _$EffectiveDeepSeekSearchRead {

 bool get effectiveEnabled; bool get effectiveFetchEnabled; ReadText get availability; ReadText? get accountId;
/// Create a copy of EffectiveDeepSeekSearchRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EffectiveDeepSeekSearchReadCopyWith<EffectiveDeepSeekSearchRead> get copyWith => _$EffectiveDeepSeekSearchReadCopyWithImpl<EffectiveDeepSeekSearchRead>(this as EffectiveDeepSeekSearchRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as EffectiveDeepSeekSearchRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EffectiveDeepSeekSearchRead&&(identical(other.effectiveEnabled, _this.effectiveEnabled) || other.effectiveEnabled == _this.effectiveEnabled)&&(identical(other.effectiveFetchEnabled, _this.effectiveFetchEnabled) || other.effectiveFetchEnabled == _this.effectiveFetchEnabled)&&(identical(other.availability, _this.availability) || other.availability == _this.availability)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId));
}


@override
int get hashCode {
  final _this = this as EffectiveDeepSeekSearchRead;
  return Object.hash(runtimeType,_this.effectiveEnabled,_this.effectiveFetchEnabled,_this.availability,_this.accountId);
}



}

/// @nodoc
abstract mixin class $EffectiveDeepSeekSearchReadCopyWith<$Res>  {
  factory $EffectiveDeepSeekSearchReadCopyWith(EffectiveDeepSeekSearchRead value, $Res Function(EffectiveDeepSeekSearchRead) _then) = _$EffectiveDeepSeekSearchReadCopyWithImpl;
@useResult
$Res call({
 bool effectiveEnabled, bool effectiveFetchEnabled, ReadText availability, ReadText? accountId
});


$ReadTextCopyWith<$Res> get availability;$ReadTextCopyWith<$Res>? get accountId;

}
/// @nodoc
class _$EffectiveDeepSeekSearchReadCopyWithImpl<$Res>
    implements $EffectiveDeepSeekSearchReadCopyWith<$Res> {
  _$EffectiveDeepSeekSearchReadCopyWithImpl(this._self, this._then);

  final EffectiveDeepSeekSearchRead _self;
  final $Res Function(EffectiveDeepSeekSearchRead) _then;

/// Create a copy of EffectiveDeepSeekSearchRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? effectiveEnabled = null,Object? effectiveFetchEnabled = null,Object? availability = null,Object? accountId = freezed,}) {
  return _then(EffectiveDeepSeekSearchRead(
effectiveEnabled: null == effectiveEnabled ? _self.effectiveEnabled : effectiveEnabled // ignore: cast_nullable_to_non_nullable
as bool,effectiveFetchEnabled: null == effectiveFetchEnabled ? _self.effectiveFetchEnabled : effectiveFetchEnabled // ignore: cast_nullable_to_non_nullable
as bool,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of EffectiveDeepSeekSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get availability {

  return $ReadTextCopyWith<$Res>(_self.availability, (value) {
    return _then(_self.copyWith(availability: value));
  });
}/// Create a copy of EffectiveDeepSeekSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get accountId {
    if (_self.accountId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.accountId!, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}
}


/// Adds pattern-matching-related methods to [EffectiveDeepSeekSearchRead].
extension EffectiveDeepSeekSearchReadPatterns on EffectiveDeepSeekSearchRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EffectiveDeepSeekSearchRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearchRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EffectiveDeepSeekSearchRead value)  $default,){
final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearchRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EffectiveDeepSeekSearchRead value)?  $default,){
final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearchRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool effectiveEnabled,  bool effectiveFetchEnabled,  ReadText availability,  ReadText? accountId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearchRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool effectiveEnabled,  bool effectiveFetchEnabled,  ReadText availability,  ReadText? accountId)  $default,) {final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearchRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool effectiveEnabled,  bool effectiveFetchEnabled,  ReadText availability,  ReadText? accountId)?  $default,) {final _that = this;
switch (_that) {
case _EffectiveDeepSeekSearchRead() when $default != null:
return $default(_that.effectiveEnabled,_that.effectiveFetchEnabled,_that.availability,_that.accountId);case _:
  return null;

}
}

}

/// @nodoc


class _EffectiveDeepSeekSearchRead implements EffectiveDeepSeekSearchRead {
  const _EffectiveDeepSeekSearchRead({required this.effectiveEnabled, required this.effectiveFetchEnabled, required this.availability, required this.accountId});


@override final  bool effectiveEnabled;
@override final  bool effectiveFetchEnabled;
@override final  ReadText availability;
@override final  ReadText? accountId;

/// Create a copy of EffectiveDeepSeekSearchRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EffectiveDeepSeekSearchReadCopyWith<_EffectiveDeepSeekSearchRead> get copyWith => __$EffectiveDeepSeekSearchReadCopyWithImpl<_EffectiveDeepSeekSearchRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _EffectiveDeepSeekSearchRead&&(identical(other.effectiveEnabled, effectiveEnabled) || other.effectiveEnabled == effectiveEnabled)&&(identical(other.effectiveFetchEnabled, effectiveFetchEnabled) || other.effectiveFetchEnabled == effectiveFetchEnabled)&&(identical(other.availability, availability) || other.availability == availability)&&(identical(other.accountId, accountId) || other.accountId == accountId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,effectiveEnabled,effectiveFetchEnabled,availability,accountId);
}



}

/// @nodoc
abstract mixin class _$EffectiveDeepSeekSearchReadCopyWith<$Res> implements $EffectiveDeepSeekSearchReadCopyWith<$Res> {
  factory _$EffectiveDeepSeekSearchReadCopyWith(_EffectiveDeepSeekSearchRead value, $Res Function(_EffectiveDeepSeekSearchRead) _then) = __$EffectiveDeepSeekSearchReadCopyWithImpl;
@override @useResult
$Res call({
 bool effectiveEnabled, bool effectiveFetchEnabled, ReadText availability, ReadText? accountId
});


@override $ReadTextCopyWith<$Res> get availability;@override $ReadTextCopyWith<$Res>? get accountId;

}
/// @nodoc
class __$EffectiveDeepSeekSearchReadCopyWithImpl<$Res>
    implements _$EffectiveDeepSeekSearchReadCopyWith<$Res> {
  __$EffectiveDeepSeekSearchReadCopyWithImpl(this._self, this._then);

  final _EffectiveDeepSeekSearchRead _self;
  final $Res Function(_EffectiveDeepSeekSearchRead) _then;

/// Create a copy of EffectiveDeepSeekSearchRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? effectiveEnabled = null,Object? effectiveFetchEnabled = null,Object? availability = null,Object? accountId = freezed,}) {
  return _then(_EffectiveDeepSeekSearchRead(
effectiveEnabled: null == effectiveEnabled ? _self.effectiveEnabled : effectiveEnabled // ignore: cast_nullable_to_non_nullable
as bool,effectiveFetchEnabled: null == effectiveFetchEnabled ? _self.effectiveFetchEnabled : effectiveFetchEnabled // ignore: cast_nullable_to_non_nullable
as bool,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as ReadText,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of EffectiveDeepSeekSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get availability {

  return $ReadTextCopyWith<$Res>(_self.availability, (value) {
    return _then(_self.copyWith(availability: value));
  });
}/// Create a copy of EffectiveDeepSeekSearchRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get accountId {
    if (_self.accountId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.accountId!, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}
}

/// @nodoc
mixin _$ModelCatalogReadHeader {

 TypedListRef get accounts; EffectiveWebSearchRead get webSearch; EffectiveDeepSeekSearchRead get deepseekWebSearch;
/// Create a copy of ModelCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogReadHeaderCopyWith<ModelCatalogReadHeader> get copyWith => _$ModelCatalogReadHeaderCopyWithImpl<ModelCatalogReadHeader>(this as ModelCatalogReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelCatalogReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogReadHeader&&(identical(other.accounts, _this.accounts) || other.accounts == _this.accounts)&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.deepseekWebSearch, _this.deepseekWebSearch) || other.deepseekWebSearch == _this.deepseekWebSearch));
}


@override
int get hashCode {
  final _this = this as ModelCatalogReadHeader;
  return Object.hash(runtimeType,_this.accounts,_this.webSearch,_this.deepseekWebSearch);
}



}

/// @nodoc
abstract mixin class $ModelCatalogReadHeaderCopyWith<$Res>  {
  factory $ModelCatalogReadHeaderCopyWith(ModelCatalogReadHeader value, $Res Function(ModelCatalogReadHeader) _then) = _$ModelCatalogReadHeaderCopyWithImpl;
@useResult
$Res call({
 TypedListRef accounts, EffectiveWebSearchRead webSearch, EffectiveDeepSeekSearchRead deepseekWebSearch
});


$TypedListRefCopyWith<$Res> get accounts;$EffectiveWebSearchReadCopyWith<$Res> get webSearch;$EffectiveDeepSeekSearchReadCopyWith<$Res> get deepseekWebSearch;

}
/// @nodoc
class _$ModelCatalogReadHeaderCopyWithImpl<$Res>
    implements $ModelCatalogReadHeaderCopyWith<$Res> {
  _$ModelCatalogReadHeaderCopyWithImpl(this._self, this._then);

  final ModelCatalogReadHeader _self;
  final $Res Function(ModelCatalogReadHeader) _then;

/// Create a copy of ModelCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accounts = null,Object? webSearch = null,Object? deepseekWebSearch = null,}) {
  return _then(ModelCatalogReadHeader(
accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as TypedListRef,webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as EffectiveWebSearchRead,deepseekWebSearch: null == deepseekWebSearch ? _self.deepseekWebSearch : deepseekWebSearch // ignore: cast_nullable_to_non_nullable
as EffectiveDeepSeekSearchRead,
  ));
}
/// Create a copy of ModelCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get accounts {

  return $TypedListRefCopyWith<$Res>(_self.accounts, (value) {
    return _then(_self.copyWith(accounts: value));
  });
}/// Create a copy of ModelCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveWebSearchReadCopyWith<$Res> get webSearch {

  return $EffectiveWebSearchReadCopyWith<$Res>(_self.webSearch, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of ModelCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveDeepSeekSearchReadCopyWith<$Res> get deepseekWebSearch {

  return $EffectiveDeepSeekSearchReadCopyWith<$Res>(_self.deepseekWebSearch, (value) {
    return _then(_self.copyWith(deepseekWebSearch: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelCatalogReadHeader].
extension ModelCatalogReadHeaderPatterns on ModelCatalogReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelCatalogReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelCatalogReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelCatalogReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelCatalogReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef accounts,  EffectiveWebSearchRead webSearch,  EffectiveDeepSeekSearchRead deepseekWebSearch)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelCatalogReadHeader() when $default != null:
return $default(_that.accounts,_that.webSearch,_that.deepseekWebSearch);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef accounts,  EffectiveWebSearchRead webSearch,  EffectiveDeepSeekSearchRead deepseekWebSearch)  $default,) {final _that = this;
switch (_that) {
case _ModelCatalogReadHeader():
return $default(_that.accounts,_that.webSearch,_that.deepseekWebSearch);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef accounts,  EffectiveWebSearchRead webSearch,  EffectiveDeepSeekSearchRead deepseekWebSearch)?  $default,) {final _that = this;
switch (_that) {
case _ModelCatalogReadHeader() when $default != null:
return $default(_that.accounts,_that.webSearch,_that.deepseekWebSearch);case _:
  return null;

}
}

}

/// @nodoc


class _ModelCatalogReadHeader implements ModelCatalogReadHeader {
  const _ModelCatalogReadHeader({required this.accounts, required this.webSearch, required this.deepseekWebSearch});


@override final  TypedListRef accounts;
@override final  EffectiveWebSearchRead webSearch;
@override final  EffectiveDeepSeekSearchRead deepseekWebSearch;

/// Create a copy of ModelCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelCatalogReadHeaderCopyWith<_ModelCatalogReadHeader> get copyWith => __$ModelCatalogReadHeaderCopyWithImpl<_ModelCatalogReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCatalogReadHeader&&(identical(other.accounts, accounts) || other.accounts == accounts)&&(identical(other.webSearch, webSearch) || other.webSearch == webSearch)&&(identical(other.deepseekWebSearch, deepseekWebSearch) || other.deepseekWebSearch == deepseekWebSearch));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accounts,webSearch,deepseekWebSearch);
}



}

/// @nodoc
abstract mixin class _$ModelCatalogReadHeaderCopyWith<$Res> implements $ModelCatalogReadHeaderCopyWith<$Res> {
  factory _$ModelCatalogReadHeaderCopyWith(_ModelCatalogReadHeader value, $Res Function(_ModelCatalogReadHeader) _then) = __$ModelCatalogReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef accounts, EffectiveWebSearchRead webSearch, EffectiveDeepSeekSearchRead deepseekWebSearch
});


@override $TypedListRefCopyWith<$Res> get accounts;@override $EffectiveWebSearchReadCopyWith<$Res> get webSearch;@override $EffectiveDeepSeekSearchReadCopyWith<$Res> get deepseekWebSearch;

}
/// @nodoc
class __$ModelCatalogReadHeaderCopyWithImpl<$Res>
    implements _$ModelCatalogReadHeaderCopyWith<$Res> {
  __$ModelCatalogReadHeaderCopyWithImpl(this._self, this._then);

  final _ModelCatalogReadHeader _self;
  final $Res Function(_ModelCatalogReadHeader) _then;

/// Create a copy of ModelCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accounts = null,Object? webSearch = null,Object? deepseekWebSearch = null,}) {
  return _then(_ModelCatalogReadHeader(
accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as TypedListRef,webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as EffectiveWebSearchRead,deepseekWebSearch: null == deepseekWebSearch ? _self.deepseekWebSearch : deepseekWebSearch // ignore: cast_nullable_to_non_nullable
as EffectiveDeepSeekSearchRead,
  ));
}

/// Create a copy of ModelCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get accounts {

  return $TypedListRefCopyWith<$Res>(_self.accounts, (value) {
    return _then(_self.copyWith(accounts: value));
  });
}/// Create a copy of ModelCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveWebSearchReadCopyWith<$Res> get webSearch {

  return $EffectiveWebSearchReadCopyWith<$Res>(_self.webSearch, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of ModelCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EffectiveDeepSeekSearchReadCopyWith<$Res> get deepseekWebSearch {

  return $EffectiveDeepSeekSearchReadCopyWith<$Res>(_self.deepseekWebSearch, (value) {
    return _then(_self.copyWith(deepseekWebSearch: value));
  });
}
}

// dart format on
