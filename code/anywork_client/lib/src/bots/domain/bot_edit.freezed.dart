// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bot_edit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BotSecretUpdate {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotSecretUpdate);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $BotSecretUpdateCopyWith<$Res>  {
$BotSecretUpdateCopyWith(BotSecretUpdate _, $Res Function(BotSecretUpdate) __);
}


/// Adds pattern-matching-related methods to [BotSecretUpdate].
extension BotSecretUpdatePatterns on BotSecretUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BotSecretPreserve value)?  preserve,TResult Function( BotSecretReplace value)?  replace,TResult Function( BotSecretClear value)?  clear,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BotSecretPreserve() when preserve != null:
return preserve(_that);case BotSecretReplace() when replace != null:
return replace(_that);case BotSecretClear() when clear != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BotSecretPreserve value)  preserve,required TResult Function( BotSecretReplace value)  replace,required TResult Function( BotSecretClear value)  clear,}){
final _that = this;
switch (_that) {
case BotSecretPreserve():
return preserve(_that);case BotSecretReplace():
return replace(_that);case BotSecretClear():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BotSecretPreserve value)?  preserve,TResult? Function( BotSecretReplace value)?  replace,TResult? Function( BotSecretClear value)?  clear,}){
final _that = this;
switch (_that) {
case BotSecretPreserve() when preserve != null:
return preserve(_that);case BotSecretReplace() when replace != null:
return replace(_that);case BotSecretClear() when clear != null:
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
case BotSecretPreserve() when preserve != null:
return preserve();case BotSecretReplace() when replace != null:
return replace(_that.value);case BotSecretClear() when clear != null:
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
case BotSecretPreserve():
return preserve();case BotSecretReplace():
return replace(_that.value);case BotSecretClear():
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
case BotSecretPreserve() when preserve != null:
return preserve();case BotSecretReplace() when replace != null:
return replace(_that.value);case BotSecretClear() when clear != null:
return clear();case _:
  return null;

}
}

}

/// @nodoc


class BotSecretPreserve extends BotSecretUpdate {
  const BotSecretPreserve(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotSecretPreserve);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class BotSecretReplace extends BotSecretUpdate {
  const BotSecretReplace({required this.value}): super._();


 final  String value;

/// Create a copy of BotSecretUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotSecretReplaceCopyWith<BotSecretReplace> get copyWith => _$BotSecretReplaceCopyWithImpl<BotSecretReplace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotSecretReplace&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $BotSecretReplaceCopyWith<$Res> implements $BotSecretUpdateCopyWith<$Res> {
  factory $BotSecretReplaceCopyWith(BotSecretReplace value, $Res Function(BotSecretReplace) _then) = _$BotSecretReplaceCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$BotSecretReplaceCopyWithImpl<$Res>
    implements $BotSecretReplaceCopyWith<$Res> {
  _$BotSecretReplaceCopyWithImpl(this._self, this._then);

  final BotSecretReplace _self;
  final $Res Function(BotSecretReplace) _then;

/// Create a copy of BotSecretUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BotSecretReplace(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BotSecretClear extends BotSecretUpdate {
  const BotSecretClear(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotSecretClear);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc
mixin _$BotEdit {

 String? get botId; int get expectedConfigRevision; String get name; String get projectId; String get appId; BotSecretUpdate get secret; bool get enabled; bool get toolsEnabled; BotModelRoute? get modelRoute;
/// Create a copy of BotEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotEditCopyWith<BotEdit> get copyWith => _$BotEditCopyWithImpl<BotEdit>(this as BotEdit, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotEdit;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotEdit&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.expectedConfigRevision, _this.expectedConfigRevision) || other.expectedConfigRevision == _this.expectedConfigRevision)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.appId, _this.appId) || other.appId == _this.appId)&&(identical(other.secret, _this.secret) || other.secret == _this.secret)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.toolsEnabled, _this.toolsEnabled) || other.toolsEnabled == _this.toolsEnabled)&&(identical(other.modelRoute, _this.modelRoute) || other.modelRoute == _this.modelRoute));
}


@override
int get hashCode {
  final _this = this as BotEdit;
  return Object.hash(runtimeType,_this.botId,_this.expectedConfigRevision,_this.name,_this.projectId,_this.appId,_this.secret,_this.enabled,_this.toolsEnabled,_this.modelRoute);
}



}

/// @nodoc
abstract mixin class $BotEditCopyWith<$Res>  {
  factory $BotEditCopyWith(BotEdit value, $Res Function(BotEdit) _then) = _$BotEditCopyWithImpl;
@useResult
$Res call({
 String? botId, int expectedConfigRevision, String name, String projectId, String appId, BotSecretUpdate secret, bool enabled, bool toolsEnabled, BotModelRoute? modelRoute
});


$BotSecretUpdateCopyWith<$Res> get secret;$BotModelRouteCopyWith<$Res>? get modelRoute;

}
/// @nodoc
class _$BotEditCopyWithImpl<$Res>
    implements $BotEditCopyWith<$Res> {
  _$BotEditCopyWithImpl(this._self, this._then);

  final BotEdit _self;
  final $Res Function(BotEdit) _then;

/// Create a copy of BotEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? botId = freezed,Object? expectedConfigRevision = null,Object? name = null,Object? projectId = null,Object? appId = null,Object? secret = null,Object? enabled = null,Object? toolsEnabled = null,Object? modelRoute = freezed,}) {
  return _then(BotEdit(
botId: freezed == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String?,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,appId: null == appId ? _self.appId : appId // ignore: cast_nullable_to_non_nullable
as String,secret: null == secret ? _self.secret : secret // ignore: cast_nullable_to_non_nullable
as BotSecretUpdate,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,toolsEnabled: null == toolsEnabled ? _self.toolsEnabled : toolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as BotModelRoute?,
  ));
}
/// Create a copy of BotEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotSecretUpdateCopyWith<$Res> get secret {

  return $BotSecretUpdateCopyWith<$Res>(_self.secret, (value) {
    return _then(_self.copyWith(secret: value));
  });
}/// Create a copy of BotEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotModelRouteCopyWith<$Res>? get modelRoute {
    if (_self.modelRoute == null) {
    return null;
  }

  return $BotModelRouteCopyWith<$Res>(_self.modelRoute!, (value) {
    return _then(_self.copyWith(modelRoute: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotEdit].
extension BotEditPatterns on BotEdit {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotEdit value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotEdit() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotEdit value)  $default,){
final _that = this;
switch (_that) {
case _BotEdit():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotEdit value)?  $default,){
final _that = this;
switch (_that) {
case _BotEdit() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? botId,  int expectedConfigRevision,  String name,  String projectId,  String appId,  BotSecretUpdate secret,  bool enabled,  bool toolsEnabled,  BotModelRoute? modelRoute)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotEdit() when $default != null:
return $default(_that.botId,_that.expectedConfigRevision,_that.name,_that.projectId,_that.appId,_that.secret,_that.enabled,_that.toolsEnabled,_that.modelRoute);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? botId,  int expectedConfigRevision,  String name,  String projectId,  String appId,  BotSecretUpdate secret,  bool enabled,  bool toolsEnabled,  BotModelRoute? modelRoute)  $default,) {final _that = this;
switch (_that) {
case _BotEdit():
return $default(_that.botId,_that.expectedConfigRevision,_that.name,_that.projectId,_that.appId,_that.secret,_that.enabled,_that.toolsEnabled,_that.modelRoute);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? botId,  int expectedConfigRevision,  String name,  String projectId,  String appId,  BotSecretUpdate secret,  bool enabled,  bool toolsEnabled,  BotModelRoute? modelRoute)?  $default,) {final _that = this;
switch (_that) {
case _BotEdit() when $default != null:
return $default(_that.botId,_that.expectedConfigRevision,_that.name,_that.projectId,_that.appId,_that.secret,_that.enabled,_that.toolsEnabled,_that.modelRoute);case _:
  return null;

}
}

}

/// @nodoc


class _BotEdit implements BotEdit {
  const _BotEdit({required this.botId, required this.expectedConfigRevision, required this.name, required this.projectId, required this.appId, required this.secret, required this.enabled, required this.toolsEnabled, required this.modelRoute});


@override final  String? botId;
@override final  int expectedConfigRevision;
@override final  String name;
@override final  String projectId;
@override final  String appId;
@override final  BotSecretUpdate secret;
@override final  bool enabled;
@override final  bool toolsEnabled;
@override final  BotModelRoute? modelRoute;

/// Create a copy of BotEdit
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotEditCopyWith<_BotEdit> get copyWith => __$BotEditCopyWithImpl<_BotEdit>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotEdit&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.expectedConfigRevision, expectedConfigRevision) || other.expectedConfigRevision == expectedConfigRevision)&&(identical(other.name, name) || other.name == name)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.appId, appId) || other.appId == appId)&&(identical(other.secret, secret) || other.secret == secret)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.toolsEnabled, toolsEnabled) || other.toolsEnabled == toolsEnabled)&&(identical(other.modelRoute, modelRoute) || other.modelRoute == modelRoute));
}


@override
int get hashCode {
    return Object.hash(runtimeType,botId,expectedConfigRevision,name,projectId,appId,secret,enabled,toolsEnabled,modelRoute);
}



}

/// @nodoc
abstract mixin class _$BotEditCopyWith<$Res> implements $BotEditCopyWith<$Res> {
  factory _$BotEditCopyWith(_BotEdit value, $Res Function(_BotEdit) _then) = __$BotEditCopyWithImpl;
@override @useResult
$Res call({
 String? botId, int expectedConfigRevision, String name, String projectId, String appId, BotSecretUpdate secret, bool enabled, bool toolsEnabled, BotModelRoute? modelRoute
});


@override $BotSecretUpdateCopyWith<$Res> get secret;@override $BotModelRouteCopyWith<$Res>? get modelRoute;

}
/// @nodoc
class __$BotEditCopyWithImpl<$Res>
    implements _$BotEditCopyWith<$Res> {
  __$BotEditCopyWithImpl(this._self, this._then);

  final _BotEdit _self;
  final $Res Function(_BotEdit) _then;

/// Create a copy of BotEdit
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? botId = freezed,Object? expectedConfigRevision = null,Object? name = null,Object? projectId = null,Object? appId = null,Object? secret = null,Object? enabled = null,Object? toolsEnabled = null,Object? modelRoute = freezed,}) {
  return _then(_BotEdit(
botId: freezed == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String?,expectedConfigRevision: null == expectedConfigRevision ? _self.expectedConfigRevision : expectedConfigRevision // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,appId: null == appId ? _self.appId : appId // ignore: cast_nullable_to_non_nullable
as String,secret: null == secret ? _self.secret : secret // ignore: cast_nullable_to_non_nullable
as BotSecretUpdate,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,toolsEnabled: null == toolsEnabled ? _self.toolsEnabled : toolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as BotModelRoute?,
  ));
}

/// Create a copy of BotEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotSecretUpdateCopyWith<$Res> get secret {

  return $BotSecretUpdateCopyWith<$Res>(_self.secret, (value) {
    return _then(_self.copyWith(secret: value));
  });
}/// Create a copy of BotEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotModelRouteCopyWith<$Res>? get modelRoute {
    if (_self.modelRoute == null) {
    return null;
  }

  return $BotModelRouteCopyWith<$Res>(_self.modelRoute!, (value) {
    return _then(_self.copyWith(modelRoute: value));
  });
}
}

// dart format on
