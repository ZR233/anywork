// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeSkillActivationCause {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillActivationCause);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeSkillActivationCause()';
}


}

/// @nodoc
class $BridgeSkillActivationCauseCopyWith<$Res>  {
$BridgeSkillActivationCauseCopyWith(BridgeSkillActivationCause _, $Res Function(BridgeSkillActivationCause) __);
}


/// Adds pattern-matching-related methods to [BridgeSkillActivationCause].
extension BridgeSkillActivationCausePatterns on BridgeSkillActivationCause {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSkillActivationCause_Tool value)?  tool,TResult Function( BridgeSkillActivationCause_UserGesture value)?  userGesture,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSkillActivationCause_Tool() when tool != null:
return tool(_that);case BridgeSkillActivationCause_UserGesture() when userGesture != null:
return userGesture(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSkillActivationCause_Tool value)  tool,required TResult Function( BridgeSkillActivationCause_UserGesture value)  userGesture,}){
final _that = this;
switch (_that) {
case BridgeSkillActivationCause_Tool():
return tool(_that);case BridgeSkillActivationCause_UserGesture():
return userGesture(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSkillActivationCause_Tool value)?  tool,TResult? Function( BridgeSkillActivationCause_UserGesture value)?  userGesture,}){
final _that = this;
switch (_that) {
case BridgeSkillActivationCause_Tool() when tool != null:
return tool(_that);case BridgeSkillActivationCause_UserGesture() when userGesture != null:
return userGesture(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String toolCallId)?  tool,TResult Function( String invocationId)?  userGesture,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSkillActivationCause_Tool() when tool != null:
return tool(_that.toolCallId);case BridgeSkillActivationCause_UserGesture() when userGesture != null:
return userGesture(_that.invocationId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String toolCallId)  tool,required TResult Function( String invocationId)  userGesture,}) {final _that = this;
switch (_that) {
case BridgeSkillActivationCause_Tool():
return tool(_that.toolCallId);case BridgeSkillActivationCause_UserGesture():
return userGesture(_that.invocationId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String toolCallId)?  tool,TResult? Function( String invocationId)?  userGesture,}) {final _that = this;
switch (_that) {
case BridgeSkillActivationCause_Tool() when tool != null:
return tool(_that.toolCallId);case BridgeSkillActivationCause_UserGesture() when userGesture != null:
return userGesture(_that.invocationId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSkillActivationCause_Tool extends BridgeSkillActivationCause {
  const BridgeSkillActivationCause_Tool({required this.toolCallId}): super._();


 final  String toolCallId;

/// Create a copy of BridgeSkillActivationCause
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillActivationCause_ToolCopyWith<BridgeSkillActivationCause_Tool> get copyWith => _$BridgeSkillActivationCause_ToolCopyWithImpl<BridgeSkillActivationCause_Tool>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillActivationCause_Tool&&(identical(other.toolCallId, toolCallId) || other.toolCallId == toolCallId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,toolCallId);
}

@override
String toString() {
    return 'BridgeSkillActivationCause.tool(toolCallId: $toolCallId)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillActivationCause_ToolCopyWith<$Res> implements $BridgeSkillActivationCauseCopyWith<$Res> {
  factory $BridgeSkillActivationCause_ToolCopyWith(BridgeSkillActivationCause_Tool value, $Res Function(BridgeSkillActivationCause_Tool) _then) = _$BridgeSkillActivationCause_ToolCopyWithImpl;
@useResult
$Res call({
 String toolCallId
});




}
/// @nodoc
class _$BridgeSkillActivationCause_ToolCopyWithImpl<$Res>
    implements $BridgeSkillActivationCause_ToolCopyWith<$Res> {
  _$BridgeSkillActivationCause_ToolCopyWithImpl(this._self, this._then);

  final BridgeSkillActivationCause_Tool _self;
  final $Res Function(BridgeSkillActivationCause_Tool) _then;

/// Create a copy of BridgeSkillActivationCause
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? toolCallId = null,}) {
  return _then(BridgeSkillActivationCause_Tool(
toolCallId: null == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeSkillActivationCause_UserGesture extends BridgeSkillActivationCause {
  const BridgeSkillActivationCause_UserGesture({required this.invocationId}): super._();


 final  String invocationId;

/// Create a copy of BridgeSkillActivationCause
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillActivationCause_UserGestureCopyWith<BridgeSkillActivationCause_UserGesture> get copyWith => _$BridgeSkillActivationCause_UserGestureCopyWithImpl<BridgeSkillActivationCause_UserGesture>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillActivationCause_UserGesture&&(identical(other.invocationId, invocationId) || other.invocationId == invocationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,invocationId);
}

@override
String toString() {
    return 'BridgeSkillActivationCause.userGesture(invocationId: $invocationId)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillActivationCause_UserGestureCopyWith<$Res> implements $BridgeSkillActivationCauseCopyWith<$Res> {
  factory $BridgeSkillActivationCause_UserGestureCopyWith(BridgeSkillActivationCause_UserGesture value, $Res Function(BridgeSkillActivationCause_UserGesture) _then) = _$BridgeSkillActivationCause_UserGestureCopyWithImpl;
@useResult
$Res call({
 String invocationId
});




}
/// @nodoc
class _$BridgeSkillActivationCause_UserGestureCopyWithImpl<$Res>
    implements $BridgeSkillActivationCause_UserGestureCopyWith<$Res> {
  _$BridgeSkillActivationCause_UserGestureCopyWithImpl(this._self, this._then);

  final BridgeSkillActivationCause_UserGesture _self;
  final $Res Function(BridgeSkillActivationCause_UserGesture) _then;

/// Create a copy of BridgeSkillActivationCause
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? invocationId = null,}) {
  return _then(BridgeSkillActivationCause_UserGesture(
invocationId: null == invocationId ? _self.invocationId : invocationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeSkillResourceBase {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillResourceBase);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeSkillResourceBase()';
}


}

/// @nodoc
class $BridgeSkillResourceBaseCopyWith<$Res>  {
$BridgeSkillResourceBaseCopyWith(BridgeSkillResourceBase _, $Res Function(BridgeSkillResourceBase) __);
}


/// Adds pattern-matching-related methods to [BridgeSkillResourceBase].
extension BridgeSkillResourceBasePatterns on BridgeSkillResourceBase {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSkillResourceBase_Directory value)?  directory,TResult Function( BridgeSkillResourceBase_Url value)?  url,TResult Function( BridgeSkillResourceBase_Opaque value)?  opaque,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSkillResourceBase_Directory() when directory != null:
return directory(_that);case BridgeSkillResourceBase_Url() when url != null:
return url(_that);case BridgeSkillResourceBase_Opaque() when opaque != null:
return opaque(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSkillResourceBase_Directory value)  directory,required TResult Function( BridgeSkillResourceBase_Url value)  url,required TResult Function( BridgeSkillResourceBase_Opaque value)  opaque,}){
final _that = this;
switch (_that) {
case BridgeSkillResourceBase_Directory():
return directory(_that);case BridgeSkillResourceBase_Url():
return url(_that);case BridgeSkillResourceBase_Opaque():
return opaque(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSkillResourceBase_Directory value)?  directory,TResult? Function( BridgeSkillResourceBase_Url value)?  url,TResult? Function( BridgeSkillResourceBase_Opaque value)?  opaque,}){
final _that = this;
switch (_that) {
case BridgeSkillResourceBase_Directory() when directory != null:
return directory(_that);case BridgeSkillResourceBase_Url() when url != null:
return url(_that);case BridgeSkillResourceBase_Opaque() when opaque != null:
return opaque(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String path)?  directory,TResult Function( String url)?  url,TResult Function( String description)?  opaque,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSkillResourceBase_Directory() when directory != null:
return directory(_that.path);case BridgeSkillResourceBase_Url() when url != null:
return url(_that.url);case BridgeSkillResourceBase_Opaque() when opaque != null:
return opaque(_that.description);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String path)  directory,required TResult Function( String url)  url,required TResult Function( String description)  opaque,}) {final _that = this;
switch (_that) {
case BridgeSkillResourceBase_Directory():
return directory(_that.path);case BridgeSkillResourceBase_Url():
return url(_that.url);case BridgeSkillResourceBase_Opaque():
return opaque(_that.description);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String path)?  directory,TResult? Function( String url)?  url,TResult? Function( String description)?  opaque,}) {final _that = this;
switch (_that) {
case BridgeSkillResourceBase_Directory() when directory != null:
return directory(_that.path);case BridgeSkillResourceBase_Url() when url != null:
return url(_that.url);case BridgeSkillResourceBase_Opaque() when opaque != null:
return opaque(_that.description);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSkillResourceBase_Directory extends BridgeSkillResourceBase {
  const BridgeSkillResourceBase_Directory({required this.path}): super._();


 final  String path;

/// Create a copy of BridgeSkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillResourceBase_DirectoryCopyWith<BridgeSkillResourceBase_Directory> get copyWith => _$BridgeSkillResourceBase_DirectoryCopyWithImpl<BridgeSkillResourceBase_Directory>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillResourceBase_Directory&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path);
}

@override
String toString() {
    return 'BridgeSkillResourceBase.directory(path: $path)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillResourceBase_DirectoryCopyWith<$Res> implements $BridgeSkillResourceBaseCopyWith<$Res> {
  factory $BridgeSkillResourceBase_DirectoryCopyWith(BridgeSkillResourceBase_Directory value, $Res Function(BridgeSkillResourceBase_Directory) _then) = _$BridgeSkillResourceBase_DirectoryCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$BridgeSkillResourceBase_DirectoryCopyWithImpl<$Res>
    implements $BridgeSkillResourceBase_DirectoryCopyWith<$Res> {
  _$BridgeSkillResourceBase_DirectoryCopyWithImpl(this._self, this._then);

  final BridgeSkillResourceBase_Directory _self;
  final $Res Function(BridgeSkillResourceBase_Directory) _then;

/// Create a copy of BridgeSkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(BridgeSkillResourceBase_Directory(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeSkillResourceBase_Url extends BridgeSkillResourceBase {
  const BridgeSkillResourceBase_Url({required this.url}): super._();


 final  String url;

/// Create a copy of BridgeSkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillResourceBase_UrlCopyWith<BridgeSkillResourceBase_Url> get copyWith => _$BridgeSkillResourceBase_UrlCopyWithImpl<BridgeSkillResourceBase_Url>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillResourceBase_Url&&(identical(other.url, url) || other.url == url));
}


@override
int get hashCode {
    return Object.hash(runtimeType,url);
}

@override
String toString() {
    return 'BridgeSkillResourceBase.url(url: $url)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillResourceBase_UrlCopyWith<$Res> implements $BridgeSkillResourceBaseCopyWith<$Res> {
  factory $BridgeSkillResourceBase_UrlCopyWith(BridgeSkillResourceBase_Url value, $Res Function(BridgeSkillResourceBase_Url) _then) = _$BridgeSkillResourceBase_UrlCopyWithImpl;
@useResult
$Res call({
 String url
});




}
/// @nodoc
class _$BridgeSkillResourceBase_UrlCopyWithImpl<$Res>
    implements $BridgeSkillResourceBase_UrlCopyWith<$Res> {
  _$BridgeSkillResourceBase_UrlCopyWithImpl(this._self, this._then);

  final BridgeSkillResourceBase_Url _self;
  final $Res Function(BridgeSkillResourceBase_Url) _then;

/// Create a copy of BridgeSkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,}) {
  return _then(BridgeSkillResourceBase_Url(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeSkillResourceBase_Opaque extends BridgeSkillResourceBase {
  const BridgeSkillResourceBase_Opaque({required this.description}): super._();


 final  String description;

/// Create a copy of BridgeSkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillResourceBase_OpaqueCopyWith<BridgeSkillResourceBase_Opaque> get copyWith => _$BridgeSkillResourceBase_OpaqueCopyWithImpl<BridgeSkillResourceBase_Opaque>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillResourceBase_Opaque&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode {
    return Object.hash(runtimeType,description);
}

@override
String toString() {
    return 'BridgeSkillResourceBase.opaque(description: $description)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillResourceBase_OpaqueCopyWith<$Res> implements $BridgeSkillResourceBaseCopyWith<$Res> {
  factory $BridgeSkillResourceBase_OpaqueCopyWith(BridgeSkillResourceBase_Opaque value, $Res Function(BridgeSkillResourceBase_Opaque) _then) = _$BridgeSkillResourceBase_OpaqueCopyWithImpl;
@useResult
$Res call({
 String description
});




}
/// @nodoc
class _$BridgeSkillResourceBase_OpaqueCopyWithImpl<$Res>
    implements $BridgeSkillResourceBase_OpaqueCopyWith<$Res> {
  _$BridgeSkillResourceBase_OpaqueCopyWithImpl(this._self, this._then);

  final BridgeSkillResourceBase_Opaque _self;
  final $Res Function(BridgeSkillResourceBase_Opaque) _then;

/// Create a copy of BridgeSkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? description = null,}) {
  return _then(BridgeSkillResourceBase_Opaque(
description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeThreadAgentState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadAgentState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadAgentState()';
}


}

/// @nodoc
class $BridgeThreadAgentStateCopyWith<$Res>  {
$BridgeThreadAgentStateCopyWith(BridgeThreadAgentState _, $Res Function(BridgeThreadAgentState) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadAgentState].
extension BridgeThreadAgentStatePatterns on BridgeThreadAgentState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadAgentState_Queued value)?  queued,TResult Function( BridgeThreadAgentState_Running value)?  running,TResult Function( BridgeThreadAgentState_Succeeded value)?  succeeded,TResult Function( BridgeThreadAgentState_Denied value)?  denied,TResult Function( BridgeThreadAgentState_Cancelled value)?  cancelled,TResult Function( BridgeThreadAgentState_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadAgentState_Queued() when queued != null:
return queued(_that);case BridgeThreadAgentState_Running() when running != null:
return running(_that);case BridgeThreadAgentState_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeThreadAgentState_Denied() when denied != null:
return denied(_that);case BridgeThreadAgentState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeThreadAgentState_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadAgentState_Queued value)  queued,required TResult Function( BridgeThreadAgentState_Running value)  running,required TResult Function( BridgeThreadAgentState_Succeeded value)  succeeded,required TResult Function( BridgeThreadAgentState_Denied value)  denied,required TResult Function( BridgeThreadAgentState_Cancelled value)  cancelled,required TResult Function( BridgeThreadAgentState_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeThreadAgentState_Queued():
return queued(_that);case BridgeThreadAgentState_Running():
return running(_that);case BridgeThreadAgentState_Succeeded():
return succeeded(_that);case BridgeThreadAgentState_Denied():
return denied(_that);case BridgeThreadAgentState_Cancelled():
return cancelled(_that);case BridgeThreadAgentState_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadAgentState_Queued value)?  queued,TResult? Function( BridgeThreadAgentState_Running value)?  running,TResult? Function( BridgeThreadAgentState_Succeeded value)?  succeeded,TResult? Function( BridgeThreadAgentState_Denied value)?  denied,TResult? Function( BridgeThreadAgentState_Cancelled value)?  cancelled,TResult? Function( BridgeThreadAgentState_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeThreadAgentState_Queued() when queued != null:
return queued(_that);case BridgeThreadAgentState_Running() when running != null:
return running(_that);case BridgeThreadAgentState_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeThreadAgentState_Denied() when denied != null:
return denied(_that);case BridgeThreadAgentState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeThreadAgentState_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  queued,TResult Function()?  running,TResult Function( PlatformInt64 completedAt,  String summary)?  succeeded,TResult Function( PlatformInt64 deniedAt,  String reason)?  denied,TResult Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,TResult Function( PlatformInt64 failedAt,  String error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadAgentState_Queued() when queued != null:
return queued();case BridgeThreadAgentState_Running() when running != null:
return running();case BridgeThreadAgentState_Succeeded() when succeeded != null:
return succeeded(_that.completedAt,_that.summary);case BridgeThreadAgentState_Denied() when denied != null:
return denied(_that.deniedAt,_that.reason);case BridgeThreadAgentState_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case BridgeThreadAgentState_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  queued,required TResult Function()  running,required TResult Function( PlatformInt64 completedAt,  String summary)  succeeded,required TResult Function( PlatformInt64 deniedAt,  String reason)  denied,required TResult Function( PlatformInt64 cancelledAt,  String reason)  cancelled,required TResult Function( PlatformInt64 failedAt,  String error)  failed,}) {final _that = this;
switch (_that) {
case BridgeThreadAgentState_Queued():
return queued();case BridgeThreadAgentState_Running():
return running();case BridgeThreadAgentState_Succeeded():
return succeeded(_that.completedAt,_that.summary);case BridgeThreadAgentState_Denied():
return denied(_that.deniedAt,_that.reason);case BridgeThreadAgentState_Cancelled():
return cancelled(_that.cancelledAt,_that.reason);case BridgeThreadAgentState_Failed():
return failed(_that.failedAt,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  queued,TResult? Function()?  running,TResult? Function( PlatformInt64 completedAt,  String summary)?  succeeded,TResult? Function( PlatformInt64 deniedAt,  String reason)?  denied,TResult? Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,TResult? Function( PlatformInt64 failedAt,  String error)?  failed,}) {final _that = this;
switch (_that) {
case BridgeThreadAgentState_Queued() when queued != null:
return queued();case BridgeThreadAgentState_Running() when running != null:
return running();case BridgeThreadAgentState_Succeeded() when succeeded != null:
return succeeded(_that.completedAt,_that.summary);case BridgeThreadAgentState_Denied() when denied != null:
return denied(_that.deniedAt,_that.reason);case BridgeThreadAgentState_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case BridgeThreadAgentState_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadAgentState_Queued extends BridgeThreadAgentState {
  const BridgeThreadAgentState_Queued(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadAgentState_Queued);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadAgentState.queued()';
}


}




/// @nodoc


class BridgeThreadAgentState_Running extends BridgeThreadAgentState {
  const BridgeThreadAgentState_Running(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadAgentState_Running);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadAgentState.running()';
}


}




/// @nodoc


class BridgeThreadAgentState_Succeeded extends BridgeThreadAgentState {
  const BridgeThreadAgentState_Succeeded({required this.completedAt, required this.summary}): super._();


 final  PlatformInt64 completedAt;
 final  String summary;

/// Create a copy of BridgeThreadAgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadAgentState_SucceededCopyWith<BridgeThreadAgentState_Succeeded> get copyWith => _$BridgeThreadAgentState_SucceededCopyWithImpl<BridgeThreadAgentState_Succeeded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadAgentState_Succeeded&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.summary, summary) || other.summary == summary));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt,summary);
}

@override
String toString() {
    return 'BridgeThreadAgentState.succeeded(completedAt: $completedAt, summary: $summary)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadAgentState_SucceededCopyWith<$Res> implements $BridgeThreadAgentStateCopyWith<$Res> {
  factory $BridgeThreadAgentState_SucceededCopyWith(BridgeThreadAgentState_Succeeded value, $Res Function(BridgeThreadAgentState_Succeeded) _then) = _$BridgeThreadAgentState_SucceededCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 completedAt, String summary
});




}
/// @nodoc
class _$BridgeThreadAgentState_SucceededCopyWithImpl<$Res>
    implements $BridgeThreadAgentState_SucceededCopyWith<$Res> {
  _$BridgeThreadAgentState_SucceededCopyWithImpl(this._self, this._then);

  final BridgeThreadAgentState_Succeeded _self;
  final $Res Function(BridgeThreadAgentState_Succeeded) _then;

/// Create a copy of BridgeThreadAgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,Object? summary = null,}) {
  return _then(BridgeThreadAgentState_Succeeded(
completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeThreadAgentState_Denied extends BridgeThreadAgentState {
  const BridgeThreadAgentState_Denied({required this.deniedAt, required this.reason}): super._();


 final  PlatformInt64 deniedAt;
 final  String reason;

/// Create a copy of BridgeThreadAgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadAgentState_DeniedCopyWith<BridgeThreadAgentState_Denied> get copyWith => _$BridgeThreadAgentState_DeniedCopyWithImpl<BridgeThreadAgentState_Denied>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadAgentState_Denied&&(identical(other.deniedAt, deniedAt) || other.deniedAt == deniedAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deniedAt,reason);
}

@override
String toString() {
    return 'BridgeThreadAgentState.denied(deniedAt: $deniedAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadAgentState_DeniedCopyWith<$Res> implements $BridgeThreadAgentStateCopyWith<$Res> {
  factory $BridgeThreadAgentState_DeniedCopyWith(BridgeThreadAgentState_Denied value, $Res Function(BridgeThreadAgentState_Denied) _then) = _$BridgeThreadAgentState_DeniedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 deniedAt, String reason
});




}
/// @nodoc
class _$BridgeThreadAgentState_DeniedCopyWithImpl<$Res>
    implements $BridgeThreadAgentState_DeniedCopyWith<$Res> {
  _$BridgeThreadAgentState_DeniedCopyWithImpl(this._self, this._then);

  final BridgeThreadAgentState_Denied _self;
  final $Res Function(BridgeThreadAgentState_Denied) _then;

/// Create a copy of BridgeThreadAgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deniedAt = null,Object? reason = null,}) {
  return _then(BridgeThreadAgentState_Denied(
deniedAt: null == deniedAt ? _self.deniedAt : deniedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeThreadAgentState_Cancelled extends BridgeThreadAgentState {
  const BridgeThreadAgentState_Cancelled({required this.cancelledAt, required this.reason}): super._();


 final  PlatformInt64 cancelledAt;
 final  String reason;

/// Create a copy of BridgeThreadAgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadAgentState_CancelledCopyWith<BridgeThreadAgentState_Cancelled> get copyWith => _$BridgeThreadAgentState_CancelledCopyWithImpl<BridgeThreadAgentState_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadAgentState_Cancelled&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}

@override
String toString() {
    return 'BridgeThreadAgentState.cancelled(cancelledAt: $cancelledAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadAgentState_CancelledCopyWith<$Res> implements $BridgeThreadAgentStateCopyWith<$Res> {
  factory $BridgeThreadAgentState_CancelledCopyWith(BridgeThreadAgentState_Cancelled value, $Res Function(BridgeThreadAgentState_Cancelled) _then) = _$BridgeThreadAgentState_CancelledCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 cancelledAt, String reason
});




}
/// @nodoc
class _$BridgeThreadAgentState_CancelledCopyWithImpl<$Res>
    implements $BridgeThreadAgentState_CancelledCopyWith<$Res> {
  _$BridgeThreadAgentState_CancelledCopyWithImpl(this._self, this._then);

  final BridgeThreadAgentState_Cancelled _self;
  final $Res Function(BridgeThreadAgentState_Cancelled) _then;

/// Create a copy of BridgeThreadAgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(BridgeThreadAgentState_Cancelled(
cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeThreadAgentState_Failed extends BridgeThreadAgentState {
  const BridgeThreadAgentState_Failed({required this.failedAt, required this.error}): super._();


 final  PlatformInt64 failedAt;
 final  String error;

/// Create a copy of BridgeThreadAgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadAgentState_FailedCopyWith<BridgeThreadAgentState_Failed> get copyWith => _$BridgeThreadAgentState_FailedCopyWithImpl<BridgeThreadAgentState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadAgentState_Failed&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,error);
}

@override
String toString() {
    return 'BridgeThreadAgentState.failed(failedAt: $failedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadAgentState_FailedCopyWith<$Res> implements $BridgeThreadAgentStateCopyWith<$Res> {
  factory $BridgeThreadAgentState_FailedCopyWith(BridgeThreadAgentState_Failed value, $Res Function(BridgeThreadAgentState_Failed) _then) = _$BridgeThreadAgentState_FailedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 failedAt, String error
});




}
/// @nodoc
class _$BridgeThreadAgentState_FailedCopyWithImpl<$Res>
    implements $BridgeThreadAgentState_FailedCopyWith<$Res> {
  _$BridgeThreadAgentState_FailedCopyWithImpl(this._self, this._then);

  final BridgeThreadAgentState_Failed _self;
  final $Res Function(BridgeThreadAgentState_Failed) _then;

/// Create a copy of BridgeThreadAgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? error = null,}) {
  return _then(BridgeThreadAgentState_Failed(
failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeThreadContentLifecycle {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadContentLifecycle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadContentLifecycle()';
}


}

/// @nodoc
class $BridgeThreadContentLifecycleCopyWith<$Res>  {
$BridgeThreadContentLifecycleCopyWith(BridgeThreadContentLifecycle _, $Res Function(BridgeThreadContentLifecycle) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadContentLifecycle].
extension BridgeThreadContentLifecyclePatterns on BridgeThreadContentLifecycle {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadContentLifecycle_Streaming value)?  streaming,TResult Function( BridgeThreadContentLifecycle_Completed value)?  completed,TResult Function( BridgeThreadContentLifecycle_Failed value)?  failed,TResult Function( BridgeThreadContentLifecycle_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadContentLifecycle_Streaming() when streaming != null:
return streaming(_that);case BridgeThreadContentLifecycle_Completed() when completed != null:
return completed(_that);case BridgeThreadContentLifecycle_Failed() when failed != null:
return failed(_that);case BridgeThreadContentLifecycle_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadContentLifecycle_Streaming value)  streaming,required TResult Function( BridgeThreadContentLifecycle_Completed value)  completed,required TResult Function( BridgeThreadContentLifecycle_Failed value)  failed,required TResult Function( BridgeThreadContentLifecycle_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case BridgeThreadContentLifecycle_Streaming():
return streaming(_that);case BridgeThreadContentLifecycle_Completed():
return completed(_that);case BridgeThreadContentLifecycle_Failed():
return failed(_that);case BridgeThreadContentLifecycle_Cancelled():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadContentLifecycle_Streaming value)?  streaming,TResult? Function( BridgeThreadContentLifecycle_Completed value)?  completed,TResult? Function( BridgeThreadContentLifecycle_Failed value)?  failed,TResult? Function( BridgeThreadContentLifecycle_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case BridgeThreadContentLifecycle_Streaming() when streaming != null:
return streaming(_that);case BridgeThreadContentLifecycle_Completed() when completed != null:
return completed(_that);case BridgeThreadContentLifecycle_Failed() when failed != null:
return failed(_that);case BridgeThreadContentLifecycle_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  streaming,TResult Function( PlatformInt64 completedAt)?  completed,TResult Function( PlatformInt64 failedAt,  String error)?  failed,TResult Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadContentLifecycle_Streaming() when streaming != null:
return streaming();case BridgeThreadContentLifecycle_Completed() when completed != null:
return completed(_that.completedAt);case BridgeThreadContentLifecycle_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case BridgeThreadContentLifecycle_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  streaming,required TResult Function( PlatformInt64 completedAt)  completed,required TResult Function( PlatformInt64 failedAt,  String error)  failed,required TResult Function( PlatformInt64 cancelledAt,  String reason)  cancelled,}) {final _that = this;
switch (_that) {
case BridgeThreadContentLifecycle_Streaming():
return streaming();case BridgeThreadContentLifecycle_Completed():
return completed(_that.completedAt);case BridgeThreadContentLifecycle_Failed():
return failed(_that.failedAt,_that.error);case BridgeThreadContentLifecycle_Cancelled():
return cancelled(_that.cancelledAt,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  streaming,TResult? Function( PlatformInt64 completedAt)?  completed,TResult? Function( PlatformInt64 failedAt,  String error)?  failed,TResult? Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,}) {final _that = this;
switch (_that) {
case BridgeThreadContentLifecycle_Streaming() when streaming != null:
return streaming();case BridgeThreadContentLifecycle_Completed() when completed != null:
return completed(_that.completedAt);case BridgeThreadContentLifecycle_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case BridgeThreadContentLifecycle_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadContentLifecycle_Streaming extends BridgeThreadContentLifecycle {
  const BridgeThreadContentLifecycle_Streaming(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadContentLifecycle_Streaming);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadContentLifecycle.streaming()';
}


}




/// @nodoc


class BridgeThreadContentLifecycle_Completed extends BridgeThreadContentLifecycle {
  const BridgeThreadContentLifecycle_Completed({required this.completedAt}): super._();


 final  PlatformInt64 completedAt;

/// Create a copy of BridgeThreadContentLifecycle
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadContentLifecycle_CompletedCopyWith<BridgeThreadContentLifecycle_Completed> get copyWith => _$BridgeThreadContentLifecycle_CompletedCopyWithImpl<BridgeThreadContentLifecycle_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadContentLifecycle_Completed&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt);
}

@override
String toString() {
    return 'BridgeThreadContentLifecycle.completed(completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadContentLifecycle_CompletedCopyWith<$Res> implements $BridgeThreadContentLifecycleCopyWith<$Res> {
  factory $BridgeThreadContentLifecycle_CompletedCopyWith(BridgeThreadContentLifecycle_Completed value, $Res Function(BridgeThreadContentLifecycle_Completed) _then) = _$BridgeThreadContentLifecycle_CompletedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 completedAt
});




}
/// @nodoc
class _$BridgeThreadContentLifecycle_CompletedCopyWithImpl<$Res>
    implements $BridgeThreadContentLifecycle_CompletedCopyWith<$Res> {
  _$BridgeThreadContentLifecycle_CompletedCopyWithImpl(this._self, this._then);

  final BridgeThreadContentLifecycle_Completed _self;
  final $Res Function(BridgeThreadContentLifecycle_Completed) _then;

/// Create a copy of BridgeThreadContentLifecycle
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,}) {
  return _then(BridgeThreadContentLifecycle_Completed(
completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeThreadContentLifecycle_Failed extends BridgeThreadContentLifecycle {
  const BridgeThreadContentLifecycle_Failed({required this.failedAt, required this.error}): super._();


 final  PlatformInt64 failedAt;
 final  String error;

/// Create a copy of BridgeThreadContentLifecycle
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadContentLifecycle_FailedCopyWith<BridgeThreadContentLifecycle_Failed> get copyWith => _$BridgeThreadContentLifecycle_FailedCopyWithImpl<BridgeThreadContentLifecycle_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadContentLifecycle_Failed&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,error);
}

@override
String toString() {
    return 'BridgeThreadContentLifecycle.failed(failedAt: $failedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadContentLifecycle_FailedCopyWith<$Res> implements $BridgeThreadContentLifecycleCopyWith<$Res> {
  factory $BridgeThreadContentLifecycle_FailedCopyWith(BridgeThreadContentLifecycle_Failed value, $Res Function(BridgeThreadContentLifecycle_Failed) _then) = _$BridgeThreadContentLifecycle_FailedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 failedAt, String error
});




}
/// @nodoc
class _$BridgeThreadContentLifecycle_FailedCopyWithImpl<$Res>
    implements $BridgeThreadContentLifecycle_FailedCopyWith<$Res> {
  _$BridgeThreadContentLifecycle_FailedCopyWithImpl(this._self, this._then);

  final BridgeThreadContentLifecycle_Failed _self;
  final $Res Function(BridgeThreadContentLifecycle_Failed) _then;

/// Create a copy of BridgeThreadContentLifecycle
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? error = null,}) {
  return _then(BridgeThreadContentLifecycle_Failed(
failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeThreadContentLifecycle_Cancelled extends BridgeThreadContentLifecycle {
  const BridgeThreadContentLifecycle_Cancelled({required this.cancelledAt, required this.reason}): super._();


 final  PlatformInt64 cancelledAt;
 final  String reason;

/// Create a copy of BridgeThreadContentLifecycle
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadContentLifecycle_CancelledCopyWith<BridgeThreadContentLifecycle_Cancelled> get copyWith => _$BridgeThreadContentLifecycle_CancelledCopyWithImpl<BridgeThreadContentLifecycle_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadContentLifecycle_Cancelled&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}

@override
String toString() {
    return 'BridgeThreadContentLifecycle.cancelled(cancelledAt: $cancelledAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadContentLifecycle_CancelledCopyWith<$Res> implements $BridgeThreadContentLifecycleCopyWith<$Res> {
  factory $BridgeThreadContentLifecycle_CancelledCopyWith(BridgeThreadContentLifecycle_Cancelled value, $Res Function(BridgeThreadContentLifecycle_Cancelled) _then) = _$BridgeThreadContentLifecycle_CancelledCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 cancelledAt, String reason
});




}
/// @nodoc
class _$BridgeThreadContentLifecycle_CancelledCopyWithImpl<$Res>
    implements $BridgeThreadContentLifecycle_CancelledCopyWith<$Res> {
  _$BridgeThreadContentLifecycle_CancelledCopyWithImpl(this._self, this._then);

  final BridgeThreadContentLifecycle_Cancelled _self;
  final $Res Function(BridgeThreadContentLifecycle_Cancelled) _then;

/// Create a copy of BridgeThreadContentLifecycle
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(BridgeThreadContentLifecycle_Cancelled(
cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeThreadInferenceState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadInferenceState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadInferenceState()';
}


}

/// @nodoc
class $BridgeThreadInferenceStateCopyWith<$Res>  {
$BridgeThreadInferenceStateCopyWith(BridgeThreadInferenceState _, $Res Function(BridgeThreadInferenceState) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadInferenceState].
extension BridgeThreadInferenceStatePatterns on BridgeThreadInferenceState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadInferenceState_Running value)?  running,TResult Function( BridgeThreadInferenceState_Completed value)?  completed,TResult Function( BridgeThreadInferenceState_Failed value)?  failed,TResult Function( BridgeThreadInferenceState_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadInferenceState_Running() when running != null:
return running(_that);case BridgeThreadInferenceState_Completed() when completed != null:
return completed(_that);case BridgeThreadInferenceState_Failed() when failed != null:
return failed(_that);case BridgeThreadInferenceState_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadInferenceState_Running value)  running,required TResult Function( BridgeThreadInferenceState_Completed value)  completed,required TResult Function( BridgeThreadInferenceState_Failed value)  failed,required TResult Function( BridgeThreadInferenceState_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case BridgeThreadInferenceState_Running():
return running(_that);case BridgeThreadInferenceState_Completed():
return completed(_that);case BridgeThreadInferenceState_Failed():
return failed(_that);case BridgeThreadInferenceState_Cancelled():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadInferenceState_Running value)?  running,TResult? Function( BridgeThreadInferenceState_Completed value)?  completed,TResult? Function( BridgeThreadInferenceState_Failed value)?  failed,TResult? Function( BridgeThreadInferenceState_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case BridgeThreadInferenceState_Running() when running != null:
return running(_that);case BridgeThreadInferenceState_Completed() when completed != null:
return completed(_that);case BridgeThreadInferenceState_Failed() when failed != null:
return failed(_that);case BridgeThreadInferenceState_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  running,TResult Function( PlatformInt64 completedAt,  BridgeTokenUsageSnapshot usage)?  completed,TResult Function( PlatformInt64 failedAt,  String error)?  failed,TResult Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadInferenceState_Running() when running != null:
return running();case BridgeThreadInferenceState_Completed() when completed != null:
return completed(_that.completedAt,_that.usage);case BridgeThreadInferenceState_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case BridgeThreadInferenceState_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  running,required TResult Function( PlatformInt64 completedAt,  BridgeTokenUsageSnapshot usage)  completed,required TResult Function( PlatformInt64 failedAt,  String error)  failed,required TResult Function( PlatformInt64 cancelledAt,  String reason)  cancelled,}) {final _that = this;
switch (_that) {
case BridgeThreadInferenceState_Running():
return running();case BridgeThreadInferenceState_Completed():
return completed(_that.completedAt,_that.usage);case BridgeThreadInferenceState_Failed():
return failed(_that.failedAt,_that.error);case BridgeThreadInferenceState_Cancelled():
return cancelled(_that.cancelledAt,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  running,TResult? Function( PlatformInt64 completedAt,  BridgeTokenUsageSnapshot usage)?  completed,TResult? Function( PlatformInt64 failedAt,  String error)?  failed,TResult? Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,}) {final _that = this;
switch (_that) {
case BridgeThreadInferenceState_Running() when running != null:
return running();case BridgeThreadInferenceState_Completed() when completed != null:
return completed(_that.completedAt,_that.usage);case BridgeThreadInferenceState_Failed() when failed != null:
return failed(_that.failedAt,_that.error);case BridgeThreadInferenceState_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadInferenceState_Running extends BridgeThreadInferenceState {
  const BridgeThreadInferenceState_Running(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadInferenceState_Running);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadInferenceState.running()';
}


}




/// @nodoc


class BridgeThreadInferenceState_Completed extends BridgeThreadInferenceState {
  const BridgeThreadInferenceState_Completed({required this.completedAt, required this.usage}): super._();


 final  PlatformInt64 completedAt;
 final  BridgeTokenUsageSnapshot usage;

/// Create a copy of BridgeThreadInferenceState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadInferenceState_CompletedCopyWith<BridgeThreadInferenceState_Completed> get copyWith => _$BridgeThreadInferenceState_CompletedCopyWithImpl<BridgeThreadInferenceState_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadInferenceState_Completed&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.usage, usage) || other.usage == usage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt,usage);
}

@override
String toString() {
    return 'BridgeThreadInferenceState.completed(completedAt: $completedAt, usage: $usage)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadInferenceState_CompletedCopyWith<$Res> implements $BridgeThreadInferenceStateCopyWith<$Res> {
  factory $BridgeThreadInferenceState_CompletedCopyWith(BridgeThreadInferenceState_Completed value, $Res Function(BridgeThreadInferenceState_Completed) _then) = _$BridgeThreadInferenceState_CompletedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 completedAt, BridgeTokenUsageSnapshot usage
});




}
/// @nodoc
class _$BridgeThreadInferenceState_CompletedCopyWithImpl<$Res>
    implements $BridgeThreadInferenceState_CompletedCopyWith<$Res> {
  _$BridgeThreadInferenceState_CompletedCopyWithImpl(this._self, this._then);

  final BridgeThreadInferenceState_Completed _self;
  final $Res Function(BridgeThreadInferenceState_Completed) _then;

/// Create a copy of BridgeThreadInferenceState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,Object? usage = null,}) {
  return _then(BridgeThreadInferenceState_Completed(
completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,usage: null == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as BridgeTokenUsageSnapshot,
  ));
}


}

/// @nodoc


class BridgeThreadInferenceState_Failed extends BridgeThreadInferenceState {
  const BridgeThreadInferenceState_Failed({required this.failedAt, required this.error}): super._();


 final  PlatformInt64 failedAt;
 final  String error;

/// Create a copy of BridgeThreadInferenceState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadInferenceState_FailedCopyWith<BridgeThreadInferenceState_Failed> get copyWith => _$BridgeThreadInferenceState_FailedCopyWithImpl<BridgeThreadInferenceState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadInferenceState_Failed&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,error);
}

@override
String toString() {
    return 'BridgeThreadInferenceState.failed(failedAt: $failedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadInferenceState_FailedCopyWith<$Res> implements $BridgeThreadInferenceStateCopyWith<$Res> {
  factory $BridgeThreadInferenceState_FailedCopyWith(BridgeThreadInferenceState_Failed value, $Res Function(BridgeThreadInferenceState_Failed) _then) = _$BridgeThreadInferenceState_FailedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 failedAt, String error
});




}
/// @nodoc
class _$BridgeThreadInferenceState_FailedCopyWithImpl<$Res>
    implements $BridgeThreadInferenceState_FailedCopyWith<$Res> {
  _$BridgeThreadInferenceState_FailedCopyWithImpl(this._self, this._then);

  final BridgeThreadInferenceState_Failed _self;
  final $Res Function(BridgeThreadInferenceState_Failed) _then;

/// Create a copy of BridgeThreadInferenceState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? error = null,}) {
  return _then(BridgeThreadInferenceState_Failed(
failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeThreadInferenceState_Cancelled extends BridgeThreadInferenceState {
  const BridgeThreadInferenceState_Cancelled({required this.cancelledAt, required this.reason}): super._();


 final  PlatformInt64 cancelledAt;
 final  String reason;

/// Create a copy of BridgeThreadInferenceState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadInferenceState_CancelledCopyWith<BridgeThreadInferenceState_Cancelled> get copyWith => _$BridgeThreadInferenceState_CancelledCopyWithImpl<BridgeThreadInferenceState_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadInferenceState_Cancelled&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}

@override
String toString() {
    return 'BridgeThreadInferenceState.cancelled(cancelledAt: $cancelledAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadInferenceState_CancelledCopyWith<$Res> implements $BridgeThreadInferenceStateCopyWith<$Res> {
  factory $BridgeThreadInferenceState_CancelledCopyWith(BridgeThreadInferenceState_Cancelled value, $Res Function(BridgeThreadInferenceState_Cancelled) _then) = _$BridgeThreadInferenceState_CancelledCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 cancelledAt, String reason
});




}
/// @nodoc
class _$BridgeThreadInferenceState_CancelledCopyWithImpl<$Res>
    implements $BridgeThreadInferenceState_CancelledCopyWith<$Res> {
  _$BridgeThreadInferenceState_CancelledCopyWithImpl(this._self, this._then);

  final BridgeThreadInferenceState_Cancelled _self;
  final $Res Function(BridgeThreadInferenceState_Cancelled) _then;

/// Create a copy of BridgeThreadInferenceState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(BridgeThreadInferenceState_Cancelled(
cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeThreadWaitIntent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadWaitIntent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadWaitIntent()';
}


}

/// @nodoc
class $BridgeThreadWaitIntentCopyWith<$Res>  {
$BridgeThreadWaitIntentCopyWith(BridgeThreadWaitIntent _, $Res Function(BridgeThreadWaitIntent) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadWaitIntent].
extension BridgeThreadWaitIntentPatterns on BridgeThreadWaitIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadWaitIntent_Events value)?  events,TResult Function( BridgeThreadWaitIntent_Timer value)?  timer,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events() when events != null:
return events(_that);case BridgeThreadWaitIntent_Timer() when timer != null:
return timer(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadWaitIntent_Events value)  events,required TResult Function( BridgeThreadWaitIntent_Timer value)  timer,}){
final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events():
return events(_that);case BridgeThreadWaitIntent_Timer():
return timer(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadWaitIntent_Events value)?  events,TResult? Function( BridgeThreadWaitIntent_Timer value)?  timer,}){
final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events() when events != null:
return events(_that);case BridgeThreadWaitIntent_Timer() when timer != null:
return timer(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<BridgeThreadWaitTarget> targets,  BigInt timeoutMs)?  events,TResult Function( BigInt durationMs)?  timer,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events() when events != null:
return events(_that.targets,_that.timeoutMs);case BridgeThreadWaitIntent_Timer() when timer != null:
return timer(_that.durationMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<BridgeThreadWaitTarget> targets,  BigInt timeoutMs)  events,required TResult Function( BigInt durationMs)  timer,}) {final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events():
return events(_that.targets,_that.timeoutMs);case BridgeThreadWaitIntent_Timer():
return timer(_that.durationMs);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<BridgeThreadWaitTarget> targets,  BigInt timeoutMs)?  events,TResult? Function( BigInt durationMs)?  timer,}) {final _that = this;
switch (_that) {
case BridgeThreadWaitIntent_Events() when events != null:
return events(_that.targets,_that.timeoutMs);case BridgeThreadWaitIntent_Timer() when timer != null:
return timer(_that.durationMs);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadWaitIntent_Events extends BridgeThreadWaitIntent {
  const BridgeThreadWaitIntent_Events({required  List<BridgeThreadWaitTarget> targets, required this.timeoutMs}): _targets = targets,super._();


 final  List<BridgeThreadWaitTarget> _targets;
 List<BridgeThreadWaitTarget> get targets {
  if (_targets is EqualUnmodifiableListView) return _targets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_targets);
}

 final  BigInt timeoutMs;

/// Create a copy of BridgeThreadWaitIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadWaitIntent_EventsCopyWith<BridgeThreadWaitIntent_Events> get copyWith => _$BridgeThreadWaitIntent_EventsCopyWithImpl<BridgeThreadWaitIntent_Events>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadWaitIntent_Events&&const DeepCollectionEquality().equals(other.targets, _targets)&&(identical(other.timeoutMs, timeoutMs) || other.timeoutMs == timeoutMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_targets),timeoutMs);
}

@override
String toString() {
    return 'BridgeThreadWaitIntent.events(targets: $targets, timeoutMs: $timeoutMs)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadWaitIntent_EventsCopyWith<$Res> implements $BridgeThreadWaitIntentCopyWith<$Res> {
  factory $BridgeThreadWaitIntent_EventsCopyWith(BridgeThreadWaitIntent_Events value, $Res Function(BridgeThreadWaitIntent_Events) _then) = _$BridgeThreadWaitIntent_EventsCopyWithImpl;
@useResult
$Res call({
 List<BridgeThreadWaitTarget> targets, BigInt timeoutMs
});




}
/// @nodoc
class _$BridgeThreadWaitIntent_EventsCopyWithImpl<$Res>
    implements $BridgeThreadWaitIntent_EventsCopyWith<$Res> {
  _$BridgeThreadWaitIntent_EventsCopyWithImpl(this._self, this._then);

  final BridgeThreadWaitIntent_Events _self;
  final $Res Function(BridgeThreadWaitIntent_Events) _then;

/// Create a copy of BridgeThreadWaitIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targets = null,Object? timeoutMs = null,}) {
  return _then(BridgeThreadWaitIntent_Events(
targets: null == targets ? _self._targets : targets // ignore: cast_nullable_to_non_nullable
as List<BridgeThreadWaitTarget>,timeoutMs: null == timeoutMs ? _self.timeoutMs : timeoutMs // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeThreadWaitIntent_Timer extends BridgeThreadWaitIntent {
  const BridgeThreadWaitIntent_Timer({required this.durationMs}): super._();


 final  BigInt durationMs;

/// Create a copy of BridgeThreadWaitIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadWaitIntent_TimerCopyWith<BridgeThreadWaitIntent_Timer> get copyWith => _$BridgeThreadWaitIntent_TimerCopyWithImpl<BridgeThreadWaitIntent_Timer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadWaitIntent_Timer&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,durationMs);
}

@override
String toString() {
    return 'BridgeThreadWaitIntent.timer(durationMs: $durationMs)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadWaitIntent_TimerCopyWith<$Res> implements $BridgeThreadWaitIntentCopyWith<$Res> {
  factory $BridgeThreadWaitIntent_TimerCopyWith(BridgeThreadWaitIntent_Timer value, $Res Function(BridgeThreadWaitIntent_Timer) _then) = _$BridgeThreadWaitIntent_TimerCopyWithImpl;
@useResult
$Res call({
 BigInt durationMs
});




}
/// @nodoc
class _$BridgeThreadWaitIntent_TimerCopyWithImpl<$Res>
    implements $BridgeThreadWaitIntent_TimerCopyWith<$Res> {
  _$BridgeThreadWaitIntent_TimerCopyWithImpl(this._self, this._then);

  final BridgeThreadWaitIntent_Timer _self;
  final $Res Function(BridgeThreadWaitIntent_Timer) _then;

/// Create a copy of BridgeThreadWaitIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? durationMs = null,}) {
  return _then(BridgeThreadWaitIntent_Timer(
durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

// dart format on
