// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_guide_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModelSelectionGuide {


/// Create a copy of ModelSelectionGuide
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelSelectionGuideCopyWith<ModelSelectionGuide> get copyWith => _$ModelSelectionGuideCopyWithImpl<ModelSelectionGuide>(this as ModelSelectionGuide, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelSelectionGuide;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelSelectionGuide&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&const DeepCollectionEquality().equals(other.taskSuitability, _this.taskSuitability)&&const DeepCollectionEquality().equals(other.limitations, _this.limitations)&&const DeepCollectionEquality().equals(other.sources, _this.sources));
}


@override
int get hashCode {
  final _this = this as ModelSelectionGuide;
  return Object.hash(runtimeType,_this.summary,const DeepCollectionEquality().hash(_this.taskSuitability),const DeepCollectionEquality().hash(_this.limitations),const DeepCollectionEquality().hash(_this.sources));
}



}

/// @nodoc
abstract mixin class $ModelSelectionGuideCopyWith<$Res>  {
  factory $ModelSelectionGuideCopyWith(ModelSelectionGuide value, $Res Function(ModelSelectionGuide) _then) = _$ModelSelectionGuideCopyWithImpl;
@useResult
$Res call({
 String summary, List<AgentTaskCategory> taskSuitability, List<String> limitations, List<ModelSelectionSource> sources
});




}
/// @nodoc
class _$ModelSelectionGuideCopyWithImpl<$Res>
    implements $ModelSelectionGuideCopyWith<$Res> {
  _$ModelSelectionGuideCopyWithImpl(this._self, this._then);

  final ModelSelectionGuide _self;
  final $Res Function(ModelSelectionGuide) _then;

/// Create a copy of ModelSelectionGuide
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? summary = null,Object? taskSuitability = null,Object? limitations = null,Object? sources = null,}) {
  return _then(ModelSelectionGuide(
summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,taskSuitability: null == taskSuitability ? _self.taskSuitability : taskSuitability // ignore: cast_nullable_to_non_nullable
as List<AgentTaskCategory>,limitations: null == limitations ? _self.limitations : limitations // ignore: cast_nullable_to_non_nullable
as List<String>,sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as List<ModelSelectionSource>,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelSelectionGuide].
extension ModelSelectionGuidePatterns on ModelSelectionGuide {
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
mixin _$ModelSelectionSource {

 ModelSelectionSourceKind get kind; String get url; int get verifiedAt; ModelSelectionMeasurement? get measurement;
/// Create a copy of ModelSelectionSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelSelectionSourceCopyWith<ModelSelectionSource> get copyWith => _$ModelSelectionSourceCopyWithImpl<ModelSelectionSource>(this as ModelSelectionSource, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelSelectionSource;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelSelectionSource&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.verifiedAt, _this.verifiedAt) || other.verifiedAt == _this.verifiedAt)&&(identical(other.measurement, _this.measurement) || other.measurement == _this.measurement));
}


@override
int get hashCode {
  final _this = this as ModelSelectionSource;
  return Object.hash(runtimeType,_this.kind,_this.url,_this.verifiedAt,_this.measurement);
}



}

/// @nodoc
abstract mixin class $ModelSelectionSourceCopyWith<$Res>  {
  factory $ModelSelectionSourceCopyWith(ModelSelectionSource value, $Res Function(ModelSelectionSource) _then) = _$ModelSelectionSourceCopyWithImpl;
@useResult
$Res call({
 ModelSelectionSourceKind kind, String url, int verifiedAt, ModelSelectionMeasurement? measurement
});


$ModelSelectionMeasurementCopyWith<$Res>? get measurement;

}
/// @nodoc
class _$ModelSelectionSourceCopyWithImpl<$Res>
    implements $ModelSelectionSourceCopyWith<$Res> {
  _$ModelSelectionSourceCopyWithImpl(this._self, this._then);

  final ModelSelectionSource _self;
  final $Res Function(ModelSelectionSource) _then;

/// Create a copy of ModelSelectionSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? url = null,Object? verifiedAt = null,Object? measurement = freezed,}) {
  return _then(ModelSelectionSource(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ModelSelectionSourceKind,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,verifiedAt: null == verifiedAt ? _self.verifiedAt : verifiedAt // ignore: cast_nullable_to_non_nullable
as int,measurement: freezed == measurement ? _self.measurement : measurement // ignore: cast_nullable_to_non_nullable
as ModelSelectionMeasurement?,
  ));
}
/// Create a copy of ModelSelectionSource
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionMeasurementCopyWith<$Res>? get measurement {
    if (_self.measurement == null) {
    return null;
  }

  return $ModelSelectionMeasurementCopyWith<$Res>(_self.measurement!, (value) {
    return _then(_self.copyWith(measurement: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelSelectionSource].
extension ModelSelectionSourcePatterns on ModelSelectionSource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelSelectionSource value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelSelectionSource() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelSelectionSource value)  $default,){
final _that = this;
switch (_that) {
case _ModelSelectionSource():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelSelectionSource value)?  $default,){
final _that = this;
switch (_that) {
case _ModelSelectionSource() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModelSelectionSourceKind kind,  String url,  int verifiedAt,  ModelSelectionMeasurement? measurement)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelSelectionSource() when $default != null:
return $default(_that.kind,_that.url,_that.verifiedAt,_that.measurement);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModelSelectionSourceKind kind,  String url,  int verifiedAt,  ModelSelectionMeasurement? measurement)  $default,) {final _that = this;
switch (_that) {
case _ModelSelectionSource():
return $default(_that.kind,_that.url,_that.verifiedAt,_that.measurement);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModelSelectionSourceKind kind,  String url,  int verifiedAt,  ModelSelectionMeasurement? measurement)?  $default,) {final _that = this;
switch (_that) {
case _ModelSelectionSource() when $default != null:
return $default(_that.kind,_that.url,_that.verifiedAt,_that.measurement);case _:
  return null;

}
}

}

/// @nodoc


class _ModelSelectionSource implements ModelSelectionSource {
  const _ModelSelectionSource({required this.kind, required this.url, required this.verifiedAt, required this.measurement});


@override final  ModelSelectionSourceKind kind;
@override final  String url;
@override final  int verifiedAt;
@override final  ModelSelectionMeasurement? measurement;

/// Create a copy of ModelSelectionSource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelSelectionSourceCopyWith<_ModelSelectionSource> get copyWith => __$ModelSelectionSourceCopyWithImpl<_ModelSelectionSource>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelSelectionSource&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.url, url) || other.url == url)&&(identical(other.verifiedAt, verifiedAt) || other.verifiedAt == verifiedAt)&&(identical(other.measurement, measurement) || other.measurement == measurement));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,url,verifiedAt,measurement);
}



}

/// @nodoc
abstract mixin class _$ModelSelectionSourceCopyWith<$Res> implements $ModelSelectionSourceCopyWith<$Res> {
  factory _$ModelSelectionSourceCopyWith(_ModelSelectionSource value, $Res Function(_ModelSelectionSource) _then) = __$ModelSelectionSourceCopyWithImpl;
@override @useResult
$Res call({
 ModelSelectionSourceKind kind, String url, int verifiedAt, ModelSelectionMeasurement? measurement
});


@override $ModelSelectionMeasurementCopyWith<$Res>? get measurement;

}
/// @nodoc
class __$ModelSelectionSourceCopyWithImpl<$Res>
    implements _$ModelSelectionSourceCopyWith<$Res> {
  __$ModelSelectionSourceCopyWithImpl(this._self, this._then);

  final _ModelSelectionSource _self;
  final $Res Function(_ModelSelectionSource) _then;

/// Create a copy of ModelSelectionSource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? url = null,Object? verifiedAt = null,Object? measurement = freezed,}) {
  return _then(_ModelSelectionSource(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ModelSelectionSourceKind,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,verifiedAt: null == verifiedAt ? _self.verifiedAt : verifiedAt // ignore: cast_nullable_to_non_nullable
as int,measurement: freezed == measurement ? _self.measurement : measurement // ignore: cast_nullable_to_non_nullable
as ModelSelectionMeasurement?,
  ));
}

/// Create a copy of ModelSelectionSource
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionMeasurementCopyWith<$Res>? get measurement {
    if (_self.measurement == null) {
    return null;
  }

  return $ModelSelectionMeasurementCopyWith<$Res>(_self.measurement!, (value) {
    return _then(_self.copyWith(measurement: value));
  });
}
}

/// @nodoc
mixin _$ModelSelectionMeasurement {

 String get model; String? get effort; String get metric; String? get metricVersion; double? get score;
/// Create a copy of ModelSelectionMeasurement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelSelectionMeasurementCopyWith<ModelSelectionMeasurement> get copyWith => _$ModelSelectionMeasurementCopyWithImpl<ModelSelectionMeasurement>(this as ModelSelectionMeasurement, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelSelectionMeasurement;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelSelectionMeasurement&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.effort, _this.effort) || other.effort == _this.effort)&&(identical(other.metric, _this.metric) || other.metric == _this.metric)&&(identical(other.metricVersion, _this.metricVersion) || other.metricVersion == _this.metricVersion)&&(identical(other.score, _this.score) || other.score == _this.score));
}


@override
int get hashCode {
  final _this = this as ModelSelectionMeasurement;
  return Object.hash(runtimeType,_this.model,_this.effort,_this.metric,_this.metricVersion,_this.score);
}



}

/// @nodoc
abstract mixin class $ModelSelectionMeasurementCopyWith<$Res>  {
  factory $ModelSelectionMeasurementCopyWith(ModelSelectionMeasurement value, $Res Function(ModelSelectionMeasurement) _then) = _$ModelSelectionMeasurementCopyWithImpl;
@useResult
$Res call({
 String model, String? effort, String metric, String? metricVersion, double? score
});




}
/// @nodoc
class _$ModelSelectionMeasurementCopyWithImpl<$Res>
    implements $ModelSelectionMeasurementCopyWith<$Res> {
  _$ModelSelectionMeasurementCopyWithImpl(this._self, this._then);

  final ModelSelectionMeasurement _self;
  final $Res Function(ModelSelectionMeasurement) _then;

/// Create a copy of ModelSelectionMeasurement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? model = null,Object? effort = freezed,Object? metric = null,Object? metricVersion = freezed,Object? score = freezed,}) {
  return _then(ModelSelectionMeasurement(
model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,metric: null == metric ? _self.metric : metric // ignore: cast_nullable_to_non_nullable
as String,metricVersion: freezed == metricVersion ? _self.metricVersion : metricVersion // ignore: cast_nullable_to_non_nullable
as String?,score: freezed == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelSelectionMeasurement].
extension ModelSelectionMeasurementPatterns on ModelSelectionMeasurement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelSelectionMeasurement value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelSelectionMeasurement() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelSelectionMeasurement value)  $default,){
final _that = this;
switch (_that) {
case _ModelSelectionMeasurement():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelSelectionMeasurement value)?  $default,){
final _that = this;
switch (_that) {
case _ModelSelectionMeasurement() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String model,  String? effort,  String metric,  String? metricVersion,  double? score)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelSelectionMeasurement() when $default != null:
return $default(_that.model,_that.effort,_that.metric,_that.metricVersion,_that.score);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String model,  String? effort,  String metric,  String? metricVersion,  double? score)  $default,) {final _that = this;
switch (_that) {
case _ModelSelectionMeasurement():
return $default(_that.model,_that.effort,_that.metric,_that.metricVersion,_that.score);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String model,  String? effort,  String metric,  String? metricVersion,  double? score)?  $default,) {final _that = this;
switch (_that) {
case _ModelSelectionMeasurement() when $default != null:
return $default(_that.model,_that.effort,_that.metric,_that.metricVersion,_that.score);case _:
  return null;

}
}

}

/// @nodoc


class _ModelSelectionMeasurement implements ModelSelectionMeasurement {
  const _ModelSelectionMeasurement({required this.model, required this.effort, required this.metric, required this.metricVersion, required this.score});


@override final  String model;
@override final  String? effort;
@override final  String metric;
@override final  String? metricVersion;
@override final  double? score;

/// Create a copy of ModelSelectionMeasurement
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelSelectionMeasurementCopyWith<_ModelSelectionMeasurement> get copyWith => __$ModelSelectionMeasurementCopyWithImpl<_ModelSelectionMeasurement>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelSelectionMeasurement&&(identical(other.model, model) || other.model == model)&&(identical(other.effort, effort) || other.effort == effort)&&(identical(other.metric, metric) || other.metric == metric)&&(identical(other.metricVersion, metricVersion) || other.metricVersion == metricVersion)&&(identical(other.score, score) || other.score == score));
}


@override
int get hashCode {
    return Object.hash(runtimeType,model,effort,metric,metricVersion,score);
}



}

/// @nodoc
abstract mixin class _$ModelSelectionMeasurementCopyWith<$Res> implements $ModelSelectionMeasurementCopyWith<$Res> {
  factory _$ModelSelectionMeasurementCopyWith(_ModelSelectionMeasurement value, $Res Function(_ModelSelectionMeasurement) _then) = __$ModelSelectionMeasurementCopyWithImpl;
@override @useResult
$Res call({
 String model, String? effort, String metric, String? metricVersion, double? score
});




}
/// @nodoc
class __$ModelSelectionMeasurementCopyWithImpl<$Res>
    implements _$ModelSelectionMeasurementCopyWith<$Res> {
  __$ModelSelectionMeasurementCopyWithImpl(this._self, this._then);

  final _ModelSelectionMeasurement _self;
  final $Res Function(_ModelSelectionMeasurement) _then;

/// Create a copy of ModelSelectionMeasurement
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? model = null,Object? effort = freezed,Object? metric = null,Object? metricVersion = freezed,Object? score = freezed,}) {
  return _then(_ModelSelectionMeasurement(
model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,metric: null == metric ? _self.metric : metric // ignore: cast_nullable_to_non_nullable
as String,metricVersion: freezed == metricVersion ? _self.metricVersion : metricVersion // ignore: cast_nullable_to_non_nullable
as String?,score: freezed == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

// dart format on
