// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'start_route_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StartRouteIntent {

 ThreadModeId get mode; AccountModelKey? get model; String? get effort;
/// Create a copy of StartRouteIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartRouteIntentCopyWith<StartRouteIntent> get copyWith => _$StartRouteIntentCopyWithImpl<StartRouteIntent>(this as StartRouteIntent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartRouteIntent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartRouteIntent&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as StartRouteIntent;
  return Object.hash(runtimeType,_this.mode,_this.model,_this.effort);
}

@override
String toString() {
  final _this = this as StartRouteIntent;
  return 'StartRouteIntent(mode: ${_this.mode}, model: ${_this.model}, effort: ${_this.effort})';
}


}

/// @nodoc
abstract mixin class $StartRouteIntentCopyWith<$Res>  {
  factory $StartRouteIntentCopyWith(StartRouteIntent value, $Res Function(StartRouteIntent) _then) = _$StartRouteIntentCopyWithImpl;
@useResult
$Res call({
 ThreadModeId mode, AccountModelKey? model, String? effort
});


$AccountModelKeyCopyWith<$Res>? get model;

}
/// @nodoc
class _$StartRouteIntentCopyWithImpl<$Res>
    implements $StartRouteIntentCopyWith<$Res> {
  _$StartRouteIntentCopyWithImpl(this._self, this._then);

  final StartRouteIntent _self;
  final $Res Function(StartRouteIntent) _then;

/// Create a copy of StartRouteIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mode = null,Object? model = freezed,Object? effort = freezed,}) {
  return _then(StartRouteIntent(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ThreadModeId,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey?,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of StartRouteIntent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res>? get model {
    if (_self.model == null) {
    return null;
  }

  return $AccountModelKeyCopyWith<$Res>(_self.model!, (value) {
    return _then(_self.copyWith(model: value));
  });
}
}


/// Adds pattern-matching-related methods to [StartRouteIntent].
extension StartRouteIntentPatterns on StartRouteIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartRouteIntent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartRouteIntent() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartRouteIntent value)  $default,){
final _that = this;
switch (_that) {
case _StartRouteIntent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartRouteIntent value)?  $default,){
final _that = this;
switch (_that) {
case _StartRouteIntent() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadModeId mode,  AccountModelKey? model,  String? effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartRouteIntent() when $default != null:
return $default(_that.mode,_that.model,_that.effort);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadModeId mode,  AccountModelKey? model,  String? effort)  $default,) {final _that = this;
switch (_that) {
case _StartRouteIntent():
return $default(_that.mode,_that.model,_that.effort);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadModeId mode,  AccountModelKey? model,  String? effort)?  $default,) {final _that = this;
switch (_that) {
case _StartRouteIntent() when $default != null:
return $default(_that.mode,_that.model,_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _StartRouteIntent implements StartRouteIntent {
  const _StartRouteIntent({required this.mode, this.model, this.effort});


@override final  ThreadModeId mode;
@override final  AccountModelKey? model;
@override final  String? effort;

/// Create a copy of StartRouteIntent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartRouteIntentCopyWith<_StartRouteIntent> get copyWith => __$StartRouteIntentCopyWithImpl<_StartRouteIntent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartRouteIntent&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.model, model) || other.model == model)&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mode,model,effort);
}

@override
String toString() {
    return 'StartRouteIntent(mode: $mode, model: $model, effort: $effort)';
}


}

/// @nodoc
abstract mixin class _$StartRouteIntentCopyWith<$Res> implements $StartRouteIntentCopyWith<$Res> {
  factory _$StartRouteIntentCopyWith(_StartRouteIntent value, $Res Function(_StartRouteIntent) _then) = __$StartRouteIntentCopyWithImpl;
@override @useResult
$Res call({
 ThreadModeId mode, AccountModelKey? model, String? effort
});


@override $AccountModelKeyCopyWith<$Res>? get model;

}
/// @nodoc
class __$StartRouteIntentCopyWithImpl<$Res>
    implements _$StartRouteIntentCopyWith<$Res> {
  __$StartRouteIntentCopyWithImpl(this._self, this._then);

  final _StartRouteIntent _self;
  final $Res Function(_StartRouteIntent) _then;

/// Create a copy of StartRouteIntent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mode = null,Object? model = freezed,Object? effort = freezed,}) {
  return _then(_StartRouteIntent(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ThreadModeId,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey?,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of StartRouteIntent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res>? get model {
    if (_self.model == null) {
    return null;
  }

  return $AccountModelKeyCopyWith<$Res>(_self.model!, (value) {
    return _then(_self.copyWith(model: value));
  });
}
}

/// @nodoc
mixin _$StartRouteQuery {

 StartRouteIntent get intent;
/// Create a copy of StartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartRouteQueryCopyWith<StartRouteQuery> get copyWith => _$StartRouteQueryCopyWithImpl<StartRouteQuery>(this as StartRouteQuery, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartRouteQuery;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartRouteQuery&&(identical(other.intent, _this.intent) || other.intent == _this.intent));
}


@override
int get hashCode {
  final _this = this as StartRouteQuery;
  return Object.hash(runtimeType,_this.intent);
}

@override
String toString() {
  final _this = this as StartRouteQuery;
  return 'StartRouteQuery(intent: ${_this.intent})';
}


}

/// @nodoc
abstract mixin class $StartRouteQueryCopyWith<$Res>  {
  factory $StartRouteQueryCopyWith(StartRouteQuery value, $Res Function(StartRouteQuery) _then) = _$StartRouteQueryCopyWithImpl;
@useResult
$Res call({
 StartRouteIntent intent
});


$StartRouteIntentCopyWith<$Res> get intent;

}
/// @nodoc
class _$StartRouteQueryCopyWithImpl<$Res>
    implements $StartRouteQueryCopyWith<$Res> {
  _$StartRouteQueryCopyWithImpl(this._self, this._then);

  final StartRouteQuery _self;
  final $Res Function(StartRouteQuery) _then;

/// Create a copy of StartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,}) {
  return _then(_self.copyWith(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as StartRouteIntent,
  ));
}
/// Create a copy of StartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteIntentCopyWith<$Res> get intent {

  return $StartRouteIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}
}


/// Adds pattern-matching-related methods to [StartRouteQuery].
extension StartRouteQueryPatterns on StartRouteQuery {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ResolveStartRouteQuery value)?  resolve,TResult Function( SelectModelStartRouteQuery value)?  selectModel,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ResolveStartRouteQuery() when resolve != null:
return resolve(_that);case SelectModelStartRouteQuery() when selectModel != null:
return selectModel(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ResolveStartRouteQuery value)  resolve,required TResult Function( SelectModelStartRouteQuery value)  selectModel,}){
final _that = this;
switch (_that) {
case ResolveStartRouteQuery():
return resolve(_that);case SelectModelStartRouteQuery():
return selectModel(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ResolveStartRouteQuery value)?  resolve,TResult? Function( SelectModelStartRouteQuery value)?  selectModel,}){
final _that = this;
switch (_that) {
case ResolveStartRouteQuery() when resolve != null:
return resolve(_that);case SelectModelStartRouteQuery() when selectModel != null:
return selectModel(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( StartRouteIntent intent)?  resolve,TResult Function( StartRouteIntent intent,  AccountModelKey selected)?  selectModel,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ResolveStartRouteQuery() when resolve != null:
return resolve(_that.intent);case SelectModelStartRouteQuery() when selectModel != null:
return selectModel(_that.intent,_that.selected);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( StartRouteIntent intent)  resolve,required TResult Function( StartRouteIntent intent,  AccountModelKey selected)  selectModel,}) {final _that = this;
switch (_that) {
case ResolveStartRouteQuery():
return resolve(_that.intent);case SelectModelStartRouteQuery():
return selectModel(_that.intent,_that.selected);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( StartRouteIntent intent)?  resolve,TResult? Function( StartRouteIntent intent,  AccountModelKey selected)?  selectModel,}) {final _that = this;
switch (_that) {
case ResolveStartRouteQuery() when resolve != null:
return resolve(_that.intent);case SelectModelStartRouteQuery() when selectModel != null:
return selectModel(_that.intent,_that.selected);case _:
  return null;

}
}

}

/// @nodoc


class ResolveStartRouteQuery implements StartRouteQuery {
  const ResolveStartRouteQuery({required this.intent});


@override final  StartRouteIntent intent;

/// Create a copy of StartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResolveStartRouteQueryCopyWith<ResolveStartRouteQuery> get copyWith => _$ResolveStartRouteQueryCopyWithImpl<ResolveStartRouteQuery>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ResolveStartRouteQuery&&(identical(other.intent, intent) || other.intent == intent));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent);
}

@override
String toString() {
    return 'StartRouteQuery.resolve(intent: $intent)';
}


}

/// @nodoc
abstract mixin class $ResolveStartRouteQueryCopyWith<$Res> implements $StartRouteQueryCopyWith<$Res> {
  factory $ResolveStartRouteQueryCopyWith(ResolveStartRouteQuery value, $Res Function(ResolveStartRouteQuery) _then) = _$ResolveStartRouteQueryCopyWithImpl;
@override @useResult
$Res call({
 StartRouteIntent intent
});


@override $StartRouteIntentCopyWith<$Res> get intent;

}
/// @nodoc
class _$ResolveStartRouteQueryCopyWithImpl<$Res>
    implements $ResolveStartRouteQueryCopyWith<$Res> {
  _$ResolveStartRouteQueryCopyWithImpl(this._self, this._then);

  final ResolveStartRouteQuery _self;
  final $Res Function(ResolveStartRouteQuery) _then;

/// Create a copy of StartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,}) {
  return _then(ResolveStartRouteQuery(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as StartRouteIntent,
  ));
}

/// Create a copy of StartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteIntentCopyWith<$Res> get intent {

  return $StartRouteIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}
}

/// @nodoc


class SelectModelStartRouteQuery implements StartRouteQuery {
  const SelectModelStartRouteQuery({required this.intent, required this.selected});


@override final  StartRouteIntent intent;
 final  AccountModelKey selected;

/// Create a copy of StartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SelectModelStartRouteQueryCopyWith<SelectModelStartRouteQuery> get copyWith => _$SelectModelStartRouteQueryCopyWithImpl<SelectModelStartRouteQuery>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SelectModelStartRouteQuery&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.selected, selected) || other.selected == selected));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,selected);
}

@override
String toString() {
    return 'StartRouteQuery.selectModel(intent: $intent, selected: $selected)';
}


}

/// @nodoc
abstract mixin class $SelectModelStartRouteQueryCopyWith<$Res> implements $StartRouteQueryCopyWith<$Res> {
  factory $SelectModelStartRouteQueryCopyWith(SelectModelStartRouteQuery value, $Res Function(SelectModelStartRouteQuery) _then) = _$SelectModelStartRouteQueryCopyWithImpl;
@override @useResult
$Res call({
 StartRouteIntent intent, AccountModelKey selected
});


@override $StartRouteIntentCopyWith<$Res> get intent;$AccountModelKeyCopyWith<$Res> get selected;

}
/// @nodoc
class _$SelectModelStartRouteQueryCopyWithImpl<$Res>
    implements $SelectModelStartRouteQueryCopyWith<$Res> {
  _$SelectModelStartRouteQueryCopyWithImpl(this._self, this._then);

  final SelectModelStartRouteQuery _self;
  final $Res Function(SelectModelStartRouteQuery) _then;

/// Create a copy of StartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? selected = null,}) {
  return _then(SelectModelStartRouteQuery(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as StartRouteIntent,selected: null == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as AccountModelKey,
  ));
}

/// Create a copy of StartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteIntentCopyWith<$Res> get intent {

  return $StartRouteIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}/// Create a copy of StartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get selected {

  return $AccountModelKeyCopyWith<$Res>(_self.selected, (value) {
    return _then(_self.copyWith(selected: value));
  });
}
}

/// @nodoc
mixin _$StartRouteRead {

 ConfigurationRoleReadTarget get sources; StartRouteQuery get query; StartRouteIntent get intent; DelegationSettings get defaults;
/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartRouteReadCopyWith<StartRouteRead> get copyWith => _$StartRouteReadCopyWithImpl<StartRouteRead>(this as StartRouteRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartRouteRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartRouteRead&&(identical(other.sources, _this.sources) || other.sources == _this.sources)&&(identical(other.query, _this.query) || other.query == _this.query)&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.defaults, _this.defaults) || other.defaults == _this.defaults));
}


@override
int get hashCode {
  final _this = this as StartRouteRead;
  return Object.hash(runtimeType,_this.sources,_this.query,_this.intent,_this.defaults);
}



}

/// @nodoc
abstract mixin class $StartRouteReadCopyWith<$Res>  {
  factory $StartRouteReadCopyWith(StartRouteRead value, $Res Function(StartRouteRead) _then) = _$StartRouteReadCopyWithImpl;
@useResult
$Res call({
 ConfigurationRoleReadTarget sources, StartRouteQuery query, StartRouteIntent intent, DelegationSettings defaults
});


$ConfigurationRoleReadTargetCopyWith<$Res> get sources;$StartRouteQueryCopyWith<$Res> get query;$StartRouteIntentCopyWith<$Res> get intent;$DelegationSettingsCopyWith<$Res> get defaults;

}
/// @nodoc
class _$StartRouteReadCopyWithImpl<$Res>
    implements $StartRouteReadCopyWith<$Res> {
  _$StartRouteReadCopyWithImpl(this._self, this._then);

  final StartRouteRead _self;
  final $Res Function(StartRouteRead) _then;

/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sources = null,Object? query = null,Object? intent = null,Object? defaults = null,}) {
  return _then(_self.copyWith(
sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as StartRouteQuery,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as StartRouteIntent,defaults: null == defaults ? _self.defaults : defaults // ignore: cast_nullable_to_non_nullable
as DelegationSettings,
  ));
}
/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res> get sources {

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteQueryCopyWith<$Res> get query {

  return $StartRouteQueryCopyWith<$Res>(_self.query, (value) {
    return _then(_self.copyWith(query: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteIntentCopyWith<$Res> get intent {

  return $StartRouteIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationSettingsCopyWith<$Res> get defaults {

  return $DelegationSettingsCopyWith<$Res>(_self.defaults, (value) {
    return _then(_self.copyWith(defaults: value));
  });
}
}


/// Adds pattern-matching-related methods to [StartRouteRead].
extension StartRouteReadPatterns on StartRouteRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ReadyStartRouteRead value)?  ready,TResult Function( UnavailableStartRouteRead value)?  unavailable,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ReadyStartRouteRead() when ready != null:
return ready(_that);case UnavailableStartRouteRead() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ReadyStartRouteRead value)  ready,required TResult Function( UnavailableStartRouteRead value)  unavailable,}){
final _that = this;
switch (_that) {
case ReadyStartRouteRead():
return ready(_that);case UnavailableStartRouteRead():
return unavailable(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ReadyStartRouteRead value)?  ready,TResult? Function( UnavailableStartRouteRead value)?  unavailable,}){
final _that = this;
switch (_that) {
case ReadyStartRouteRead() when ready != null:
return ready(_that);case UnavailableStartRouteRead() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ConfigurationRoleReadTarget sources,  StartRouteQuery query,  StartRouteIntent intent,  ModelSelection route,  DelegationSettings defaults)?  ready,TResult Function( ConfigurationRoleReadTarget sources,  StartRouteQuery query,  StartRouteIntent intent,  ModelSelection? desired,  DelegationSettings defaults,  StudioFailure error)?  unavailable,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ReadyStartRouteRead() when ready != null:
return ready(_that.sources,_that.query,_that.intent,_that.route,_that.defaults);case UnavailableStartRouteRead() when unavailable != null:
return unavailable(_that.sources,_that.query,_that.intent,_that.desired,_that.defaults,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ConfigurationRoleReadTarget sources,  StartRouteQuery query,  StartRouteIntent intent,  ModelSelection route,  DelegationSettings defaults)  ready,required TResult Function( ConfigurationRoleReadTarget sources,  StartRouteQuery query,  StartRouteIntent intent,  ModelSelection? desired,  DelegationSettings defaults,  StudioFailure error)  unavailable,}) {final _that = this;
switch (_that) {
case ReadyStartRouteRead():
return ready(_that.sources,_that.query,_that.intent,_that.route,_that.defaults);case UnavailableStartRouteRead():
return unavailable(_that.sources,_that.query,_that.intent,_that.desired,_that.defaults,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ConfigurationRoleReadTarget sources,  StartRouteQuery query,  StartRouteIntent intent,  ModelSelection route,  DelegationSettings defaults)?  ready,TResult? Function( ConfigurationRoleReadTarget sources,  StartRouteQuery query,  StartRouteIntent intent,  ModelSelection? desired,  DelegationSettings defaults,  StudioFailure error)?  unavailable,}) {final _that = this;
switch (_that) {
case ReadyStartRouteRead() when ready != null:
return ready(_that.sources,_that.query,_that.intent,_that.route,_that.defaults);case UnavailableStartRouteRead() when unavailable != null:
return unavailable(_that.sources,_that.query,_that.intent,_that.desired,_that.defaults,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class ReadyStartRouteRead implements StartRouteRead {
  const ReadyStartRouteRead({required this.sources, required this.query, required this.intent, required this.route, required this.defaults});


@override final  ConfigurationRoleReadTarget sources;
@override final  StartRouteQuery query;
@override final  StartRouteIntent intent;
 final  ModelSelection route;
@override final  DelegationSettings defaults;

/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyStartRouteReadCopyWith<ReadyStartRouteRead> get copyWith => _$ReadyStartRouteReadCopyWithImpl<ReadyStartRouteRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyStartRouteRead&&(identical(other.sources, sources) || other.sources == sources)&&(identical(other.query, query) || other.query == query)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.route, route) || other.route == route)&&(identical(other.defaults, defaults) || other.defaults == defaults));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sources,query,intent,route,defaults);
}



}

/// @nodoc
abstract mixin class $ReadyStartRouteReadCopyWith<$Res> implements $StartRouteReadCopyWith<$Res> {
  factory $ReadyStartRouteReadCopyWith(ReadyStartRouteRead value, $Res Function(ReadyStartRouteRead) _then) = _$ReadyStartRouteReadCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationRoleReadTarget sources, StartRouteQuery query, StartRouteIntent intent, ModelSelection route, DelegationSettings defaults
});


@override $ConfigurationRoleReadTargetCopyWith<$Res> get sources;@override $StartRouteQueryCopyWith<$Res> get query;@override $StartRouteIntentCopyWith<$Res> get intent;$ModelSelectionCopyWith<$Res> get route;@override $DelegationSettingsCopyWith<$Res> get defaults;

}
/// @nodoc
class _$ReadyStartRouteReadCopyWithImpl<$Res>
    implements $ReadyStartRouteReadCopyWith<$Res> {
  _$ReadyStartRouteReadCopyWithImpl(this._self, this._then);

  final ReadyStartRouteRead _self;
  final $Res Function(ReadyStartRouteRead) _then;

/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sources = null,Object? query = null,Object? intent = null,Object? route = null,Object? defaults = null,}) {
  return _then(ReadyStartRouteRead(
sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as StartRouteQuery,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as StartRouteIntent,route: null == route ? _self.route : route // ignore: cast_nullable_to_non_nullable
as ModelSelection,defaults: null == defaults ? _self.defaults : defaults // ignore: cast_nullable_to_non_nullable
as DelegationSettings,
  ));
}

/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res> get sources {

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteQueryCopyWith<$Res> get query {

  return $StartRouteQueryCopyWith<$Res>(_self.query, (value) {
    return _then(_self.copyWith(query: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteIntentCopyWith<$Res> get intent {

  return $StartRouteIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res> get route {

  return $ModelSelectionCopyWith<$Res>(_self.route, (value) {
    return _then(_self.copyWith(route: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationSettingsCopyWith<$Res> get defaults {

  return $DelegationSettingsCopyWith<$Res>(_self.defaults, (value) {
    return _then(_self.copyWith(defaults: value));
  });
}
}

/// @nodoc


class UnavailableStartRouteRead implements StartRouteRead {
  const UnavailableStartRouteRead({required this.sources, required this.query, required this.intent, required this.desired, required this.defaults, required this.error});


@override final  ConfigurationRoleReadTarget sources;
@override final  StartRouteQuery query;
@override final  StartRouteIntent intent;
 final  ModelSelection? desired;
@override final  DelegationSettings defaults;
 final  StudioFailure error;

/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnavailableStartRouteReadCopyWith<UnavailableStartRouteRead> get copyWith => _$UnavailableStartRouteReadCopyWithImpl<UnavailableStartRouteRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnavailableStartRouteRead&&(identical(other.sources, sources) || other.sources == sources)&&(identical(other.query, query) || other.query == query)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.desired, desired) || other.desired == desired)&&(identical(other.defaults, defaults) || other.defaults == defaults)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sources,query,intent,desired,defaults,error);
}



}

/// @nodoc
abstract mixin class $UnavailableStartRouteReadCopyWith<$Res> implements $StartRouteReadCopyWith<$Res> {
  factory $UnavailableStartRouteReadCopyWith(UnavailableStartRouteRead value, $Res Function(UnavailableStartRouteRead) _then) = _$UnavailableStartRouteReadCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationRoleReadTarget sources, StartRouteQuery query, StartRouteIntent intent, ModelSelection? desired, DelegationSettings defaults, StudioFailure error
});


@override $ConfigurationRoleReadTargetCopyWith<$Res> get sources;@override $StartRouteQueryCopyWith<$Res> get query;@override $StartRouteIntentCopyWith<$Res> get intent;$ModelSelectionCopyWith<$Res>? get desired;@override $DelegationSettingsCopyWith<$Res> get defaults;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$UnavailableStartRouteReadCopyWithImpl<$Res>
    implements $UnavailableStartRouteReadCopyWith<$Res> {
  _$UnavailableStartRouteReadCopyWithImpl(this._self, this._then);

  final UnavailableStartRouteRead _self;
  final $Res Function(UnavailableStartRouteRead) _then;

/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sources = null,Object? query = null,Object? intent = null,Object? desired = freezed,Object? defaults = null,Object? error = null,}) {
  return _then(UnavailableStartRouteRead(
sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as StartRouteQuery,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as StartRouteIntent,desired: freezed == desired ? _self.desired : desired // ignore: cast_nullable_to_non_nullable
as ModelSelection?,defaults: null == defaults ? _self.defaults : defaults // ignore: cast_nullable_to_non_nullable
as DelegationSettings,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res> get sources {

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.sources, (value) {
    return _then(_self.copyWith(sources: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteQueryCopyWith<$Res> get query {

  return $StartRouteQueryCopyWith<$Res>(_self.query, (value) {
    return _then(_self.copyWith(query: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteIntentCopyWith<$Res> get intent {

  return $StartRouteIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res>? get desired {
    if (_self.desired == null) {
    return null;
  }

  return $ModelSelectionCopyWith<$Res>(_self.desired!, (value) {
    return _then(_self.copyWith(desired: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationSettingsCopyWith<$Res> get defaults {

  return $DelegationSettingsCopyWith<$Res>(_self.defaults, (value) {
    return _then(_self.copyWith(defaults: value));
  });
}/// Create a copy of StartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
