// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'configuration_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeRoleRouteRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRoleRouteRead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeRoleRouteRead()';
}


}

/// @nodoc
class $BridgeRoleRouteReadCopyWith<$Res>  {
$BridgeRoleRouteReadCopyWith(BridgeRoleRouteRead _, $Res Function(BridgeRoleRouteRead) __);
}


/// Adds pattern-matching-related methods to [BridgeRoleRouteRead].
extension BridgeRoleRouteReadPatterns on BridgeRoleRouteRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeRoleRouteRead_Configured value)?  configured,TResult Function( BridgeRoleRouteRead_Missing value)?  missing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeRoleRouteRead_Configured() when configured != null:
return configured(_that);case BridgeRoleRouteRead_Missing() when missing != null:
return missing(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeRoleRouteRead_Configured value)  configured,required TResult Function( BridgeRoleRouteRead_Missing value)  missing,}){
final _that = this;
switch (_that) {
case BridgeRoleRouteRead_Configured():
return configured(_that);case BridgeRoleRouteRead_Missing():
return missing(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeRoleRouteRead_Configured value)?  configured,TResult? Function( BridgeRoleRouteRead_Missing value)?  missing,}){
final _that = this;
switch (_that) {
case BridgeRoleRouteRead_Configured() when configured != null:
return configured(_that);case BridgeRoleRouteRead_Missing() when missing != null:
return missing(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeConfiguredRoleRoute route)?  configured,TResult Function( BridgeModelSelection? suggestion)?  missing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeRoleRouteRead_Configured() when configured != null:
return configured(_that.route);case BridgeRoleRouteRead_Missing() when missing != null:
return missing(_that.suggestion);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeConfiguredRoleRoute route)  configured,required TResult Function( BridgeModelSelection? suggestion)  missing,}) {final _that = this;
switch (_that) {
case BridgeRoleRouteRead_Configured():
return configured(_that.route);case BridgeRoleRouteRead_Missing():
return missing(_that.suggestion);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeConfiguredRoleRoute route)?  configured,TResult? Function( BridgeModelSelection? suggestion)?  missing,}) {final _that = this;
switch (_that) {
case BridgeRoleRouteRead_Configured() when configured != null:
return configured(_that.route);case BridgeRoleRouteRead_Missing() when missing != null:
return missing(_that.suggestion);case _:
  return null;

}
}

}

/// @nodoc


class BridgeRoleRouteRead_Configured extends BridgeRoleRouteRead {
  const BridgeRoleRouteRead_Configured({required this.route}): super._();


 final  BridgeConfiguredRoleRoute route;

/// Create a copy of BridgeRoleRouteRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRoleRouteRead_ConfiguredCopyWith<BridgeRoleRouteRead_Configured> get copyWith => _$BridgeRoleRouteRead_ConfiguredCopyWithImpl<BridgeRoleRouteRead_Configured>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRoleRouteRead_Configured&&(identical(other.route, route) || other.route == route));
}


@override
int get hashCode {
    return Object.hash(runtimeType,route);
}

@override
String toString() {
    return 'BridgeRoleRouteRead.configured(route: $route)';
}


}

/// @nodoc
abstract mixin class $BridgeRoleRouteRead_ConfiguredCopyWith<$Res> implements $BridgeRoleRouteReadCopyWith<$Res> {
  factory $BridgeRoleRouteRead_ConfiguredCopyWith(BridgeRoleRouteRead_Configured value, $Res Function(BridgeRoleRouteRead_Configured) _then) = _$BridgeRoleRouteRead_ConfiguredCopyWithImpl;
@useResult
$Res call({
 BridgeConfiguredRoleRoute route
});




}
/// @nodoc
class _$BridgeRoleRouteRead_ConfiguredCopyWithImpl<$Res>
    implements $BridgeRoleRouteRead_ConfiguredCopyWith<$Res> {
  _$BridgeRoleRouteRead_ConfiguredCopyWithImpl(this._self, this._then);

  final BridgeRoleRouteRead_Configured _self;
  final $Res Function(BridgeRoleRouteRead_Configured) _then;

/// Create a copy of BridgeRoleRouteRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? route = null,}) {
  return _then(BridgeRoleRouteRead_Configured(
route: null == route ? _self.route : route // ignore: cast_nullable_to_non_nullable
as BridgeConfiguredRoleRoute,
  ));
}


}

/// @nodoc


class BridgeRoleRouteRead_Missing extends BridgeRoleRouteRead {
  const BridgeRoleRouteRead_Missing({this.suggestion}): super._();


 final  BridgeModelSelection? suggestion;

/// Create a copy of BridgeRoleRouteRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRoleRouteRead_MissingCopyWith<BridgeRoleRouteRead_Missing> get copyWith => _$BridgeRoleRouteRead_MissingCopyWithImpl<BridgeRoleRouteRead_Missing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRoleRouteRead_Missing&&(identical(other.suggestion, suggestion) || other.suggestion == suggestion));
}


@override
int get hashCode {
    return Object.hash(runtimeType,suggestion);
}

@override
String toString() {
    return 'BridgeRoleRouteRead.missing(suggestion: $suggestion)';
}


}

/// @nodoc
abstract mixin class $BridgeRoleRouteRead_MissingCopyWith<$Res> implements $BridgeRoleRouteReadCopyWith<$Res> {
  factory $BridgeRoleRouteRead_MissingCopyWith(BridgeRoleRouteRead_Missing value, $Res Function(BridgeRoleRouteRead_Missing) _then) = _$BridgeRoleRouteRead_MissingCopyWithImpl;
@useResult
$Res call({
 BridgeModelSelection? suggestion
});




}
/// @nodoc
class _$BridgeRoleRouteRead_MissingCopyWithImpl<$Res>
    implements $BridgeRoleRouteRead_MissingCopyWith<$Res> {
  _$BridgeRoleRouteRead_MissingCopyWithImpl(this._self, this._then);

  final BridgeRoleRouteRead_Missing _self;
  final $Res Function(BridgeRoleRouteRead_Missing) _then;

/// Create a copy of BridgeRoleRouteRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? suggestion = freezed,}) {
  return _then(BridgeRoleRouteRead_Missing(
suggestion: freezed == suggestion ? _self.suggestion : suggestion // ignore: cast_nullable_to_non_nullable
as BridgeModelSelection?,
  ));
}


}

/// @nodoc
mixin _$BridgeStartRouteQuery {

 BridgeStartRouteIntent get intent;
/// Create a copy of BridgeStartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStartRouteQueryCopyWith<BridgeStartRouteQuery> get copyWith => _$BridgeStartRouteQueryCopyWithImpl<BridgeStartRouteQuery>(this as BridgeStartRouteQuery, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeStartRouteQuery;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStartRouteQuery&&(identical(other.intent, _this.intent) || other.intent == _this.intent));
}


@override
int get hashCode {
  final _this = this as BridgeStartRouteQuery;
  return Object.hash(runtimeType,_this.intent);
}

@override
String toString() {
  final _this = this as BridgeStartRouteQuery;
  return 'BridgeStartRouteQuery(intent: ${_this.intent})';
}


}

/// @nodoc
abstract mixin class $BridgeStartRouteQueryCopyWith<$Res>  {
  factory $BridgeStartRouteQueryCopyWith(BridgeStartRouteQuery value, $Res Function(BridgeStartRouteQuery) _then) = _$BridgeStartRouteQueryCopyWithImpl;
@useResult
$Res call({
 BridgeStartRouteIntent intent
});




}
/// @nodoc
class _$BridgeStartRouteQueryCopyWithImpl<$Res>
    implements $BridgeStartRouteQueryCopyWith<$Res> {
  _$BridgeStartRouteQueryCopyWithImpl(this._self, this._then);

  final BridgeStartRouteQuery _self;
  final $Res Function(BridgeStartRouteQuery) _then;

/// Create a copy of BridgeStartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,}) {
  return _then(_self.copyWith(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as BridgeStartRouteIntent,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeStartRouteQuery].
extension BridgeStartRouteQueryPatterns on BridgeStartRouteQuery {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeStartRouteQuery_Resolve value)?  resolve,TResult Function( BridgeStartRouteQuery_SelectModel value)?  selectModel,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeStartRouteQuery_Resolve() when resolve != null:
return resolve(_that);case BridgeStartRouteQuery_SelectModel() when selectModel != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeStartRouteQuery_Resolve value)  resolve,required TResult Function( BridgeStartRouteQuery_SelectModel value)  selectModel,}){
final _that = this;
switch (_that) {
case BridgeStartRouteQuery_Resolve():
return resolve(_that);case BridgeStartRouteQuery_SelectModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeStartRouteQuery_Resolve value)?  resolve,TResult? Function( BridgeStartRouteQuery_SelectModel value)?  selectModel,}){
final _that = this;
switch (_that) {
case BridgeStartRouteQuery_Resolve() when resolve != null:
return resolve(_that);case BridgeStartRouteQuery_SelectModel() when selectModel != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeStartRouteIntent intent)?  resolve,TResult Function( BridgeStartRouteIntent intent,  BridgeAccountModelKey selected)?  selectModel,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeStartRouteQuery_Resolve() when resolve != null:
return resolve(_that.intent);case BridgeStartRouteQuery_SelectModel() when selectModel != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeStartRouteIntent intent)  resolve,required TResult Function( BridgeStartRouteIntent intent,  BridgeAccountModelKey selected)  selectModel,}) {final _that = this;
switch (_that) {
case BridgeStartRouteQuery_Resolve():
return resolve(_that.intent);case BridgeStartRouteQuery_SelectModel():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeStartRouteIntent intent)?  resolve,TResult? Function( BridgeStartRouteIntent intent,  BridgeAccountModelKey selected)?  selectModel,}) {final _that = this;
switch (_that) {
case BridgeStartRouteQuery_Resolve() when resolve != null:
return resolve(_that.intent);case BridgeStartRouteQuery_SelectModel() when selectModel != null:
return selectModel(_that.intent,_that.selected);case _:
  return null;

}
}

}

/// @nodoc


class BridgeStartRouteQuery_Resolve extends BridgeStartRouteQuery {
  const BridgeStartRouteQuery_Resolve({required this.intent}): super._();


@override final  BridgeStartRouteIntent intent;

/// Create a copy of BridgeStartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStartRouteQuery_ResolveCopyWith<BridgeStartRouteQuery_Resolve> get copyWith => _$BridgeStartRouteQuery_ResolveCopyWithImpl<BridgeStartRouteQuery_Resolve>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStartRouteQuery_Resolve&&(identical(other.intent, intent) || other.intent == intent));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent);
}

@override
String toString() {
    return 'BridgeStartRouteQuery.resolve(intent: $intent)';
}


}

/// @nodoc
abstract mixin class $BridgeStartRouteQuery_ResolveCopyWith<$Res> implements $BridgeStartRouteQueryCopyWith<$Res> {
  factory $BridgeStartRouteQuery_ResolveCopyWith(BridgeStartRouteQuery_Resolve value, $Res Function(BridgeStartRouteQuery_Resolve) _then) = _$BridgeStartRouteQuery_ResolveCopyWithImpl;
@override @useResult
$Res call({
 BridgeStartRouteIntent intent
});




}
/// @nodoc
class _$BridgeStartRouteQuery_ResolveCopyWithImpl<$Res>
    implements $BridgeStartRouteQuery_ResolveCopyWith<$Res> {
  _$BridgeStartRouteQuery_ResolveCopyWithImpl(this._self, this._then);

  final BridgeStartRouteQuery_Resolve _self;
  final $Res Function(BridgeStartRouteQuery_Resolve) _then;

/// Create a copy of BridgeStartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,}) {
  return _then(BridgeStartRouteQuery_Resolve(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as BridgeStartRouteIntent,
  ));
}


}

/// @nodoc


class BridgeStartRouteQuery_SelectModel extends BridgeStartRouteQuery {
  const BridgeStartRouteQuery_SelectModel({required this.intent, required this.selected}): super._();


@override final  BridgeStartRouteIntent intent;
 final  BridgeAccountModelKey selected;

/// Create a copy of BridgeStartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStartRouteQuery_SelectModelCopyWith<BridgeStartRouteQuery_SelectModel> get copyWith => _$BridgeStartRouteQuery_SelectModelCopyWithImpl<BridgeStartRouteQuery_SelectModel>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStartRouteQuery_SelectModel&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.selected, selected) || other.selected == selected));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,selected);
}

@override
String toString() {
    return 'BridgeStartRouteQuery.selectModel(intent: $intent, selected: $selected)';
}


}

/// @nodoc
abstract mixin class $BridgeStartRouteQuery_SelectModelCopyWith<$Res> implements $BridgeStartRouteQueryCopyWith<$Res> {
  factory $BridgeStartRouteQuery_SelectModelCopyWith(BridgeStartRouteQuery_SelectModel value, $Res Function(BridgeStartRouteQuery_SelectModel) _then) = _$BridgeStartRouteQuery_SelectModelCopyWithImpl;
@override @useResult
$Res call({
 BridgeStartRouteIntent intent, BridgeAccountModelKey selected
});




}
/// @nodoc
class _$BridgeStartRouteQuery_SelectModelCopyWithImpl<$Res>
    implements $BridgeStartRouteQuery_SelectModelCopyWith<$Res> {
  _$BridgeStartRouteQuery_SelectModelCopyWithImpl(this._self, this._then);

  final BridgeStartRouteQuery_SelectModel _self;
  final $Res Function(BridgeStartRouteQuery_SelectModel) _then;

/// Create a copy of BridgeStartRouteQuery
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? selected = null,}) {
  return _then(BridgeStartRouteQuery_SelectModel(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as BridgeStartRouteIntent,selected: null == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as BridgeAccountModelKey,
  ));
}


}

/// @nodoc
mixin _$BridgeStartRouteRead {

 BridgeConfigurationRoleReadTarget get sources; BridgeStartRouteQuery get query; BridgeStartRouteIntent get intent; BridgeDelegationSettings get defaults;
/// Create a copy of BridgeStartRouteRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStartRouteReadCopyWith<BridgeStartRouteRead> get copyWith => _$BridgeStartRouteReadCopyWithImpl<BridgeStartRouteRead>(this as BridgeStartRouteRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeStartRouteRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStartRouteRead&&(identical(other.sources, _this.sources) || other.sources == _this.sources)&&(identical(other.query, _this.query) || other.query == _this.query)&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.defaults, _this.defaults) || other.defaults == _this.defaults));
}


@override
int get hashCode {
  final _this = this as BridgeStartRouteRead;
  return Object.hash(runtimeType,_this.sources,_this.query,_this.intent,_this.defaults);
}

@override
String toString() {
  final _this = this as BridgeStartRouteRead;
  return 'BridgeStartRouteRead(sources: ${_this.sources}, query: ${_this.query}, intent: ${_this.intent}, defaults: ${_this.defaults})';
}


}

/// @nodoc
abstract mixin class $BridgeStartRouteReadCopyWith<$Res>  {
  factory $BridgeStartRouteReadCopyWith(BridgeStartRouteRead value, $Res Function(BridgeStartRouteRead) _then) = _$BridgeStartRouteReadCopyWithImpl;
@useResult
$Res call({
 BridgeConfigurationRoleReadTarget sources, BridgeStartRouteQuery query, BridgeStartRouteIntent intent, BridgeDelegationSettings defaults
});


$BridgeStartRouteQueryCopyWith<$Res> get query;

}
/// @nodoc
class _$BridgeStartRouteReadCopyWithImpl<$Res>
    implements $BridgeStartRouteReadCopyWith<$Res> {
  _$BridgeStartRouteReadCopyWithImpl(this._self, this._then);

  final BridgeStartRouteRead _self;
  final $Res Function(BridgeStartRouteRead) _then;

/// Create a copy of BridgeStartRouteRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sources = null,Object? query = null,Object? intent = null,Object? defaults = null,}) {
  return _then(_self.copyWith(
sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as BridgeConfigurationRoleReadTarget,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as BridgeStartRouteQuery,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as BridgeStartRouteIntent,defaults: null == defaults ? _self.defaults : defaults // ignore: cast_nullable_to_non_nullable
as BridgeDelegationSettings,
  ));
}
/// Create a copy of BridgeStartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeStartRouteQueryCopyWith<$Res> get query {

  return $BridgeStartRouteQueryCopyWith<$Res>(_self.query, (value) {
    return _then(_self.copyWith(query: value));
  });
}
}


/// Adds pattern-matching-related methods to [BridgeStartRouteRead].
extension BridgeStartRouteReadPatterns on BridgeStartRouteRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeStartRouteRead_Ready value)?  ready,TResult Function( BridgeStartRouteRead_Unavailable value)?  unavailable,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeStartRouteRead_Ready() when ready != null:
return ready(_that);case BridgeStartRouteRead_Unavailable() when unavailable != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeStartRouteRead_Ready value)  ready,required TResult Function( BridgeStartRouteRead_Unavailable value)  unavailable,}){
final _that = this;
switch (_that) {
case BridgeStartRouteRead_Ready():
return ready(_that);case BridgeStartRouteRead_Unavailable():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeStartRouteRead_Ready value)?  ready,TResult? Function( BridgeStartRouteRead_Unavailable value)?  unavailable,}){
final _that = this;
switch (_that) {
case BridgeStartRouteRead_Ready() when ready != null:
return ready(_that);case BridgeStartRouteRead_Unavailable() when unavailable != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeConfigurationRoleReadTarget sources,  BridgeStartRouteQuery query,  BridgeStartRouteIntent intent,  BridgeModelSelection route,  BridgeDelegationSettings defaults)?  ready,TResult Function( BridgeConfigurationRoleReadTarget sources,  BridgeStartRouteQuery query,  BridgeStartRouteIntent intent,  BridgeModelSelection? desired,  BridgeDelegationSettings defaults,  BridgeError error)?  unavailable,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeStartRouteRead_Ready() when ready != null:
return ready(_that.sources,_that.query,_that.intent,_that.route,_that.defaults);case BridgeStartRouteRead_Unavailable() when unavailable != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeConfigurationRoleReadTarget sources,  BridgeStartRouteQuery query,  BridgeStartRouteIntent intent,  BridgeModelSelection route,  BridgeDelegationSettings defaults)  ready,required TResult Function( BridgeConfigurationRoleReadTarget sources,  BridgeStartRouteQuery query,  BridgeStartRouteIntent intent,  BridgeModelSelection? desired,  BridgeDelegationSettings defaults,  BridgeError error)  unavailable,}) {final _that = this;
switch (_that) {
case BridgeStartRouteRead_Ready():
return ready(_that.sources,_that.query,_that.intent,_that.route,_that.defaults);case BridgeStartRouteRead_Unavailable():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeConfigurationRoleReadTarget sources,  BridgeStartRouteQuery query,  BridgeStartRouteIntent intent,  BridgeModelSelection route,  BridgeDelegationSettings defaults)?  ready,TResult? Function( BridgeConfigurationRoleReadTarget sources,  BridgeStartRouteQuery query,  BridgeStartRouteIntent intent,  BridgeModelSelection? desired,  BridgeDelegationSettings defaults,  BridgeError error)?  unavailable,}) {final _that = this;
switch (_that) {
case BridgeStartRouteRead_Ready() when ready != null:
return ready(_that.sources,_that.query,_that.intent,_that.route,_that.defaults);case BridgeStartRouteRead_Unavailable() when unavailable != null:
return unavailable(_that.sources,_that.query,_that.intent,_that.desired,_that.defaults,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeStartRouteRead_Ready extends BridgeStartRouteRead {
  const BridgeStartRouteRead_Ready({required this.sources, required this.query, required this.intent, required this.route, required this.defaults}): super._();


@override final  BridgeConfigurationRoleReadTarget sources;
@override final  BridgeStartRouteQuery query;
@override final  BridgeStartRouteIntent intent;
 final  BridgeModelSelection route;
@override final  BridgeDelegationSettings defaults;

/// Create a copy of BridgeStartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStartRouteRead_ReadyCopyWith<BridgeStartRouteRead_Ready> get copyWith => _$BridgeStartRouteRead_ReadyCopyWithImpl<BridgeStartRouteRead_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStartRouteRead_Ready&&(identical(other.sources, sources) || other.sources == sources)&&(identical(other.query, query) || other.query == query)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.route, route) || other.route == route)&&(identical(other.defaults, defaults) || other.defaults == defaults));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sources,query,intent,route,defaults);
}

@override
String toString() {
    return 'BridgeStartRouteRead.ready(sources: $sources, query: $query, intent: $intent, route: $route, defaults: $defaults)';
}


}

/// @nodoc
abstract mixin class $BridgeStartRouteRead_ReadyCopyWith<$Res> implements $BridgeStartRouteReadCopyWith<$Res> {
  factory $BridgeStartRouteRead_ReadyCopyWith(BridgeStartRouteRead_Ready value, $Res Function(BridgeStartRouteRead_Ready) _then) = _$BridgeStartRouteRead_ReadyCopyWithImpl;
@override @useResult
$Res call({
 BridgeConfigurationRoleReadTarget sources, BridgeStartRouteQuery query, BridgeStartRouteIntent intent, BridgeModelSelection route, BridgeDelegationSettings defaults
});


@override $BridgeStartRouteQueryCopyWith<$Res> get query;

}
/// @nodoc
class _$BridgeStartRouteRead_ReadyCopyWithImpl<$Res>
    implements $BridgeStartRouteRead_ReadyCopyWith<$Res> {
  _$BridgeStartRouteRead_ReadyCopyWithImpl(this._self, this._then);

  final BridgeStartRouteRead_Ready _self;
  final $Res Function(BridgeStartRouteRead_Ready) _then;

/// Create a copy of BridgeStartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sources = null,Object? query = null,Object? intent = null,Object? route = null,Object? defaults = null,}) {
  return _then(BridgeStartRouteRead_Ready(
sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as BridgeConfigurationRoleReadTarget,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as BridgeStartRouteQuery,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as BridgeStartRouteIntent,route: null == route ? _self.route : route // ignore: cast_nullable_to_non_nullable
as BridgeModelSelection,defaults: null == defaults ? _self.defaults : defaults // ignore: cast_nullable_to_non_nullable
as BridgeDelegationSettings,
  ));
}

/// Create a copy of BridgeStartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeStartRouteQueryCopyWith<$Res> get query {

  return $BridgeStartRouteQueryCopyWith<$Res>(_self.query, (value) {
    return _then(_self.copyWith(query: value));
  });
}
}

/// @nodoc


class BridgeStartRouteRead_Unavailable extends BridgeStartRouteRead {
  const BridgeStartRouteRead_Unavailable({required this.sources, required this.query, required this.intent, this.desired, required this.defaults, required this.error}): super._();


@override final  BridgeConfigurationRoleReadTarget sources;
@override final  BridgeStartRouteQuery query;
@override final  BridgeStartRouteIntent intent;
 final  BridgeModelSelection? desired;
@override final  BridgeDelegationSettings defaults;
 final  BridgeError error;

/// Create a copy of BridgeStartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStartRouteRead_UnavailableCopyWith<BridgeStartRouteRead_Unavailable> get copyWith => _$BridgeStartRouteRead_UnavailableCopyWithImpl<BridgeStartRouteRead_Unavailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStartRouteRead_Unavailable&&(identical(other.sources, sources) || other.sources == sources)&&(identical(other.query, query) || other.query == query)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.desired, desired) || other.desired == desired)&&(identical(other.defaults, defaults) || other.defaults == defaults)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sources,query,intent,desired,defaults,error);
}

@override
String toString() {
    return 'BridgeStartRouteRead.unavailable(sources: $sources, query: $query, intent: $intent, desired: $desired, defaults: $defaults, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeStartRouteRead_UnavailableCopyWith<$Res> implements $BridgeStartRouteReadCopyWith<$Res> {
  factory $BridgeStartRouteRead_UnavailableCopyWith(BridgeStartRouteRead_Unavailable value, $Res Function(BridgeStartRouteRead_Unavailable) _then) = _$BridgeStartRouteRead_UnavailableCopyWithImpl;
@override @useResult
$Res call({
 BridgeConfigurationRoleReadTarget sources, BridgeStartRouteQuery query, BridgeStartRouteIntent intent, BridgeModelSelection? desired, BridgeDelegationSettings defaults, BridgeError error
});


@override $BridgeStartRouteQueryCopyWith<$Res> get query;

}
/// @nodoc
class _$BridgeStartRouteRead_UnavailableCopyWithImpl<$Res>
    implements $BridgeStartRouteRead_UnavailableCopyWith<$Res> {
  _$BridgeStartRouteRead_UnavailableCopyWithImpl(this._self, this._then);

  final BridgeStartRouteRead_Unavailable _self;
  final $Res Function(BridgeStartRouteRead_Unavailable) _then;

/// Create a copy of BridgeStartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sources = null,Object? query = null,Object? intent = null,Object? desired = freezed,Object? defaults = null,Object? error = null,}) {
  return _then(BridgeStartRouteRead_Unavailable(
sources: null == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as BridgeConfigurationRoleReadTarget,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as BridgeStartRouteQuery,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as BridgeStartRouteIntent,desired: freezed == desired ? _self.desired : desired // ignore: cast_nullable_to_non_nullable
as BridgeModelSelection?,defaults: null == defaults ? _self.defaults : defaults // ignore: cast_nullable_to_non_nullable
as BridgeDelegationSettings,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}

/// Create a copy of BridgeStartRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeStartRouteQueryCopyWith<$Res> get query {

  return $BridgeStartRouteQueryCopyWith<$Res>(_self.query, (value) {
    return _then(_self.copyWith(query: value));
  });
}
}

// dart format on
