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
