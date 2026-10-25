// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'skills_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SkillInvocationPolicy {

 bool get modelInvocable; bool get userInvocable;
/// Create a copy of SkillInvocationPolicy
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillInvocationPolicyCopyWith<SkillInvocationPolicy> get copyWith => _$SkillInvocationPolicyCopyWithImpl<SkillInvocationPolicy>(this as SkillInvocationPolicy, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillInvocationPolicy;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillInvocationPolicy&&(identical(other.modelInvocable, _this.modelInvocable) || other.modelInvocable == _this.modelInvocable)&&(identical(other.userInvocable, _this.userInvocable) || other.userInvocable == _this.userInvocable));
}


@override
int get hashCode {
  final _this = this as SkillInvocationPolicy;
  return Object.hash(runtimeType,_this.modelInvocable,_this.userInvocable);
}

@override
String toString() {
  final _this = this as SkillInvocationPolicy;
  return 'SkillInvocationPolicy(modelInvocable: ${_this.modelInvocable}, userInvocable: ${_this.userInvocable})';
}


}

/// @nodoc
abstract mixin class $SkillInvocationPolicyCopyWith<$Res>  {
  factory $SkillInvocationPolicyCopyWith(SkillInvocationPolicy value, $Res Function(SkillInvocationPolicy) _then) = _$SkillInvocationPolicyCopyWithImpl;
@useResult
$Res call({
 bool modelInvocable, bool userInvocable
});




}
/// @nodoc
class _$SkillInvocationPolicyCopyWithImpl<$Res>
    implements $SkillInvocationPolicyCopyWith<$Res> {
  _$SkillInvocationPolicyCopyWithImpl(this._self, this._then);

  final SkillInvocationPolicy _self;
  final $Res Function(SkillInvocationPolicy) _then;

/// Create a copy of SkillInvocationPolicy
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelInvocable = null,Object? userInvocable = null,}) {
  return _then(SkillInvocationPolicy(
modelInvocable: null == modelInvocable ? _self.modelInvocable : modelInvocable // ignore: cast_nullable_to_non_nullable
as bool,userInvocable: null == userInvocable ? _self.userInvocable : userInvocable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SkillInvocationPolicy].
extension SkillInvocationPolicyPatterns on SkillInvocationPolicy {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillInvocationPolicy value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillInvocationPolicy() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillInvocationPolicy value)  $default,){
final _that = this;
switch (_that) {
case _SkillInvocationPolicy():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillInvocationPolicy value)?  $default,){
final _that = this;
switch (_that) {
case _SkillInvocationPolicy() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool modelInvocable,  bool userInvocable)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillInvocationPolicy() when $default != null:
return $default(_that.modelInvocable,_that.userInvocable);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool modelInvocable,  bool userInvocable)  $default,) {final _that = this;
switch (_that) {
case _SkillInvocationPolicy():
return $default(_that.modelInvocable,_that.userInvocable);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool modelInvocable,  bool userInvocable)?  $default,) {final _that = this;
switch (_that) {
case _SkillInvocationPolicy() when $default != null:
return $default(_that.modelInvocable,_that.userInvocable);case _:
  return null;

}
}

}

/// @nodoc


class _SkillInvocationPolicy implements SkillInvocationPolicy {
  const _SkillInvocationPolicy({required this.modelInvocable, required this.userInvocable});


@override final  bool modelInvocable;
@override final  bool userInvocable;

/// Create a copy of SkillInvocationPolicy
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillInvocationPolicyCopyWith<_SkillInvocationPolicy> get copyWith => __$SkillInvocationPolicyCopyWithImpl<_SkillInvocationPolicy>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillInvocationPolicy&&(identical(other.modelInvocable, modelInvocable) || other.modelInvocable == modelInvocable)&&(identical(other.userInvocable, userInvocable) || other.userInvocable == userInvocable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelInvocable,userInvocable);
}

@override
String toString() {
    return 'SkillInvocationPolicy(modelInvocable: $modelInvocable, userInvocable: $userInvocable)';
}


}

/// @nodoc
abstract mixin class _$SkillInvocationPolicyCopyWith<$Res> implements $SkillInvocationPolicyCopyWith<$Res> {
  factory _$SkillInvocationPolicyCopyWith(_SkillInvocationPolicy value, $Res Function(_SkillInvocationPolicy) _then) = __$SkillInvocationPolicyCopyWithImpl;
@override @useResult
$Res call({
 bool modelInvocable, bool userInvocable
});




}
/// @nodoc
class __$SkillInvocationPolicyCopyWithImpl<$Res>
    implements _$SkillInvocationPolicyCopyWith<$Res> {
  __$SkillInvocationPolicyCopyWithImpl(this._self, this._then);

  final _SkillInvocationPolicy _self;
  final $Res Function(_SkillInvocationPolicy) _then;

/// Create a copy of SkillInvocationPolicy
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelInvocable = null,Object? userInvocable = null,}) {
  return _then(_SkillInvocationPolicy(
modelInvocable: null == modelInvocable ? _self.modelInvocable : modelInvocable // ignore: cast_nullable_to_non_nullable
as bool,userInvocable: null == userInvocable ? _self.userInvocable : userInvocable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$SkillResourceBase {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillResourceBase);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $SkillResourceBaseCopyWith<$Res>  {
$SkillResourceBaseCopyWith(SkillResourceBase _, $Res Function(SkillResourceBase) __);
}


/// Adds pattern-matching-related methods to [SkillResourceBase].
extension SkillResourceBasePatterns on SkillResourceBase {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DirectorySkillResourceBase value)?  directory,TResult Function( UrlSkillResourceBase value)?  url,TResult Function( OpaqueSkillResourceBase value)?  opaque,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DirectorySkillResourceBase() when directory != null:
return directory(_that);case UrlSkillResourceBase() when url != null:
return url(_that);case OpaqueSkillResourceBase() when opaque != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DirectorySkillResourceBase value)  directory,required TResult Function( UrlSkillResourceBase value)  url,required TResult Function( OpaqueSkillResourceBase value)  opaque,}){
final _that = this;
switch (_that) {
case DirectorySkillResourceBase():
return directory(_that);case UrlSkillResourceBase():
return url(_that);case OpaqueSkillResourceBase():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DirectorySkillResourceBase value)?  directory,TResult? Function( UrlSkillResourceBase value)?  url,TResult? Function( OpaqueSkillResourceBase value)?  opaque,}){
final _that = this;
switch (_that) {
case DirectorySkillResourceBase() when directory != null:
return directory(_that);case UrlSkillResourceBase() when url != null:
return url(_that);case OpaqueSkillResourceBase() when opaque != null:
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
case DirectorySkillResourceBase() when directory != null:
return directory(_that.path);case UrlSkillResourceBase() when url != null:
return url(_that.url);case OpaqueSkillResourceBase() when opaque != null:
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
case DirectorySkillResourceBase():
return directory(_that.path);case UrlSkillResourceBase():
return url(_that.url);case OpaqueSkillResourceBase():
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
case DirectorySkillResourceBase() when directory != null:
return directory(_that.path);case UrlSkillResourceBase() when url != null:
return url(_that.url);case OpaqueSkillResourceBase() when opaque != null:
return opaque(_that.description);case _:
  return null;

}
}

}

/// @nodoc


class DirectorySkillResourceBase implements SkillResourceBase {
  const DirectorySkillResourceBase({required this.path});


 final  String path;

/// Create a copy of SkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DirectorySkillResourceBaseCopyWith<DirectorySkillResourceBase> get copyWith => _$DirectorySkillResourceBaseCopyWithImpl<DirectorySkillResourceBase>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DirectorySkillResourceBase&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path);
}



}

/// @nodoc
abstract mixin class $DirectorySkillResourceBaseCopyWith<$Res> implements $SkillResourceBaseCopyWith<$Res> {
  factory $DirectorySkillResourceBaseCopyWith(DirectorySkillResourceBase value, $Res Function(DirectorySkillResourceBase) _then) = _$DirectorySkillResourceBaseCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$DirectorySkillResourceBaseCopyWithImpl<$Res>
    implements $DirectorySkillResourceBaseCopyWith<$Res> {
  _$DirectorySkillResourceBaseCopyWithImpl(this._self, this._then);

  final DirectorySkillResourceBase _self;
  final $Res Function(DirectorySkillResourceBase) _then;

/// Create a copy of SkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(DirectorySkillResourceBase(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class UrlSkillResourceBase implements SkillResourceBase {
  const UrlSkillResourceBase({required this.url});


 final  String url;

/// Create a copy of SkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UrlSkillResourceBaseCopyWith<UrlSkillResourceBase> get copyWith => _$UrlSkillResourceBaseCopyWithImpl<UrlSkillResourceBase>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UrlSkillResourceBase&&(identical(other.url, url) || other.url == url));
}


@override
int get hashCode {
    return Object.hash(runtimeType,url);
}



}

/// @nodoc
abstract mixin class $UrlSkillResourceBaseCopyWith<$Res> implements $SkillResourceBaseCopyWith<$Res> {
  factory $UrlSkillResourceBaseCopyWith(UrlSkillResourceBase value, $Res Function(UrlSkillResourceBase) _then) = _$UrlSkillResourceBaseCopyWithImpl;
@useResult
$Res call({
 String url
});




}
/// @nodoc
class _$UrlSkillResourceBaseCopyWithImpl<$Res>
    implements $UrlSkillResourceBaseCopyWith<$Res> {
  _$UrlSkillResourceBaseCopyWithImpl(this._self, this._then);

  final UrlSkillResourceBase _self;
  final $Res Function(UrlSkillResourceBase) _then;

/// Create a copy of SkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,}) {
  return _then(UrlSkillResourceBase(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class OpaqueSkillResourceBase implements SkillResourceBase {
  const OpaqueSkillResourceBase({required this.description});


 final  String description;

/// Create a copy of SkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OpaqueSkillResourceBaseCopyWith<OpaqueSkillResourceBase> get copyWith => _$OpaqueSkillResourceBaseCopyWithImpl<OpaqueSkillResourceBase>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is OpaqueSkillResourceBase&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode {
    return Object.hash(runtimeType,description);
}



}

/// @nodoc
abstract mixin class $OpaqueSkillResourceBaseCopyWith<$Res> implements $SkillResourceBaseCopyWith<$Res> {
  factory $OpaqueSkillResourceBaseCopyWith(OpaqueSkillResourceBase value, $Res Function(OpaqueSkillResourceBase) _then) = _$OpaqueSkillResourceBaseCopyWithImpl;
@useResult
$Res call({
 String description
});




}
/// @nodoc
class _$OpaqueSkillResourceBaseCopyWithImpl<$Res>
    implements $OpaqueSkillResourceBaseCopyWith<$Res> {
  _$OpaqueSkillResourceBaseCopyWithImpl(this._self, this._then);

  final OpaqueSkillResourceBase _self;
  final $Res Function(OpaqueSkillResourceBase) _then;

/// Create a copy of SkillResourceBase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? description = null,}) {
  return _then(OpaqueSkillResourceBase(
description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SkillSummary {


/// Create a copy of SkillSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillSummaryCopyWith<SkillSummary> get copyWith => _$SkillSummaryCopyWithImpl<SkillSummary>(this as SkillSummary, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillSummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillSummary&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.category, _this.category) || other.category == _this.category)&&const DeepCollectionEquality().equals(other.platforms, _this.platforms)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.providerId, _this.providerId) || other.providerId == _this.providerId)&&(identical(other.invocation, _this.invocation) || other.invocation == _this.invocation)&&(identical(other.resourceBase, _this.resourceBase) || other.resourceBase == _this.resourceBase));
}


@override
int get hashCode {
  final _this = this as SkillSummary;
  return Object.hash(runtimeType,_this.name,_this.description,_this.category,const DeepCollectionEquality().hash(_this.platforms),_this.source,_this.providerId,_this.invocation,_this.resourceBase);
}



}

/// @nodoc
abstract mixin class $SkillSummaryCopyWith<$Res>  {
  factory $SkillSummaryCopyWith(SkillSummary value, $Res Function(SkillSummary) _then) = _$SkillSummaryCopyWithImpl;
@useResult
$Res call({
 String name, String description, String? category, List<String> platforms, SkillSource source, String providerId, SkillInvocationPolicy invocation, SkillResourceBase resourceBase
});


$SkillInvocationPolicyCopyWith<$Res> get invocation;$SkillResourceBaseCopyWith<$Res> get resourceBase;

}
/// @nodoc
class _$SkillSummaryCopyWithImpl<$Res>
    implements $SkillSummaryCopyWith<$Res> {
  _$SkillSummaryCopyWithImpl(this._self, this._then);

  final SkillSummary _self;
  final $Res Function(SkillSummary) _then;

/// Create a copy of SkillSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? description = null,Object? category = freezed,Object? platforms = null,Object? source = null,Object? providerId = null,Object? invocation = null,Object? resourceBase = null,}) {
  return _then(SkillSummary(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,platforms: null == platforms ? _self.platforms : platforms // ignore: cast_nullable_to_non_nullable
as List<String>,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SkillSource,providerId: null == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as String,invocation: null == invocation ? _self.invocation : invocation // ignore: cast_nullable_to_non_nullable
as SkillInvocationPolicy,resourceBase: null == resourceBase ? _self.resourceBase : resourceBase // ignore: cast_nullable_to_non_nullable
as SkillResourceBase,
  ));
}
/// Create a copy of SkillSummary
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillInvocationPolicyCopyWith<$Res> get invocation {

  return $SkillInvocationPolicyCopyWith<$Res>(_self.invocation, (value) {
    return _then(_self.copyWith(invocation: value));
  });
}/// Create a copy of SkillSummary
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillResourceBaseCopyWith<$Res> get resourceBase {

  return $SkillResourceBaseCopyWith<$Res>(_self.resourceBase, (value) {
    return _then(_self.copyWith(resourceBase: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillSummary].
extension SkillSummaryPatterns on SkillSummary {
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
mixin _$SkillCatalogValue {


/// Create a copy of SkillCatalogValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillCatalogValueCopyWith<SkillCatalogValue> get copyWith => _$SkillCatalogValueCopyWithImpl<SkillCatalogValue>(this as SkillCatalogValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillCatalogValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillCatalogValue&&(identical(other.projectDir, _this.projectDir) || other.projectDir == _this.projectDir)&&const DeepCollectionEquality().equals(other.skills, _this.skills)&&const DeepCollectionEquality().equals(other.warnings, _this.warnings)&&(identical(other.complete, _this.complete) || other.complete == _this.complete));
}


@override
int get hashCode {
  final _this = this as SkillCatalogValue;
  return Object.hash(runtimeType,_this.projectDir,const DeepCollectionEquality().hash(_this.skills),const DeepCollectionEquality().hash(_this.warnings),_this.complete);
}



}

/// @nodoc
abstract mixin class $SkillCatalogValueCopyWith<$Res>  {
  factory $SkillCatalogValueCopyWith(SkillCatalogValue value, $Res Function(SkillCatalogValue) _then) = _$SkillCatalogValueCopyWithImpl;
@useResult
$Res call({
 String projectDir, List<SkillSummary> skills, List<String> warnings, bool complete
});




}
/// @nodoc
class _$SkillCatalogValueCopyWithImpl<$Res>
    implements $SkillCatalogValueCopyWith<$Res> {
  _$SkillCatalogValueCopyWithImpl(this._self, this._then);

  final SkillCatalogValue _self;
  final $Res Function(SkillCatalogValue) _then;

/// Create a copy of SkillCatalogValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectDir = null,Object? skills = null,Object? warnings = null,Object? complete = null,}) {
  return _then(SkillCatalogValue(
projectDir: null == projectDir ? _self.projectDir : projectDir // ignore: cast_nullable_to_non_nullable
as String,skills: null == skills ? _self.skills : skills // ignore: cast_nullable_to_non_nullable
as List<SkillSummary>,warnings: null == warnings ? _self.warnings : warnings // ignore: cast_nullable_to_non_nullable
as List<String>,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SkillCatalogValue].
extension SkillCatalogValuePatterns on SkillCatalogValue {
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
mixin _$SkillsValue {

 String get projectId; String get configFingerprint; int get catalogRevision; SkillCatalogValue get catalog;
/// Create a copy of SkillsValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsValueCopyWith<SkillsValue> get copyWith => _$SkillsValueCopyWithImpl<SkillsValue>(this as SkillsValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsValue&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.configFingerprint, _this.configFingerprint) || other.configFingerprint == _this.configFingerprint)&&(identical(other.catalogRevision, _this.catalogRevision) || other.catalogRevision == _this.catalogRevision)&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog));
}


@override
int get hashCode {
  final _this = this as SkillsValue;
  return Object.hash(runtimeType,_this.projectId,_this.configFingerprint,_this.catalogRevision,_this.catalog);
}



}

/// @nodoc
abstract mixin class $SkillsValueCopyWith<$Res>  {
  factory $SkillsValueCopyWith(SkillsValue value, $Res Function(SkillsValue) _then) = _$SkillsValueCopyWithImpl;
@useResult
$Res call({
 String projectId, String configFingerprint, int catalogRevision, SkillCatalogValue catalog
});


$SkillCatalogValueCopyWith<$Res> get catalog;

}
/// @nodoc
class _$SkillsValueCopyWithImpl<$Res>
    implements $SkillsValueCopyWith<$Res> {
  _$SkillsValueCopyWithImpl(this._self, this._then);

  final SkillsValue _self;
  final $Res Function(SkillsValue) _then;

/// Create a copy of SkillsValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? configFingerprint = null,Object? catalogRevision = null,Object? catalog = null,}) {
  return _then(SkillsValue(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,configFingerprint: null == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as String,catalogRevision: null == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as SkillCatalogValue,
  ));
}
/// Create a copy of SkillsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillCatalogValueCopyWith<$Res> get catalog {

  return $SkillCatalogValueCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillsValue].
extension SkillsValuePatterns on SkillsValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillsValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillsValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillsValue value)  $default,){
final _that = this;
switch (_that) {
case _SkillsValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillsValue value)?  $default,){
final _that = this;
switch (_that) {
case _SkillsValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String projectId,  String configFingerprint,  int catalogRevision,  SkillCatalogValue catalog)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillsValue() when $default != null:
return $default(_that.projectId,_that.configFingerprint,_that.catalogRevision,_that.catalog);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String projectId,  String configFingerprint,  int catalogRevision,  SkillCatalogValue catalog)  $default,) {final _that = this;
switch (_that) {
case _SkillsValue():
return $default(_that.projectId,_that.configFingerprint,_that.catalogRevision,_that.catalog);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String projectId,  String configFingerprint,  int catalogRevision,  SkillCatalogValue catalog)?  $default,) {final _that = this;
switch (_that) {
case _SkillsValue() when $default != null:
return $default(_that.projectId,_that.configFingerprint,_that.catalogRevision,_that.catalog);case _:
  return null;

}
}

}

/// @nodoc


class _SkillsValue implements SkillsValue {
  const _SkillsValue({required this.projectId, required this.configFingerprint, required this.catalogRevision, required this.catalog});


@override final  String projectId;
@override final  String configFingerprint;
@override final  int catalogRevision;
@override final  SkillCatalogValue catalog;

/// Create a copy of SkillsValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillsValueCopyWith<_SkillsValue> get copyWith => __$SkillsValueCopyWithImpl<_SkillsValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillsValue&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.configFingerprint, configFingerprint) || other.configFingerprint == configFingerprint)&&(identical(other.catalogRevision, catalogRevision) || other.catalogRevision == catalogRevision)&&(identical(other.catalog, catalog) || other.catalog == catalog));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projectId,configFingerprint,catalogRevision,catalog);
}



}

/// @nodoc
abstract mixin class _$SkillsValueCopyWith<$Res> implements $SkillsValueCopyWith<$Res> {
  factory _$SkillsValueCopyWith(_SkillsValue value, $Res Function(_SkillsValue) _then) = __$SkillsValueCopyWithImpl;
@override @useResult
$Res call({
 String projectId, String configFingerprint, int catalogRevision, SkillCatalogValue catalog
});


@override $SkillCatalogValueCopyWith<$Res> get catalog;

}
/// @nodoc
class __$SkillsValueCopyWithImpl<$Res>
    implements _$SkillsValueCopyWith<$Res> {
  __$SkillsValueCopyWithImpl(this._self, this._then);

  final _SkillsValue _self;
  final $Res Function(_SkillsValue) _then;

/// Create a copy of SkillsValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = null,Object? configFingerprint = null,Object? catalogRevision = null,Object? catalog = null,}) {
  return _then(_SkillsValue(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,configFingerprint: null == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as String,catalogRevision: null == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as SkillCatalogValue,
  ));
}

/// Create a copy of SkillsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillCatalogValueCopyWith<$Res> get catalog {

  return $SkillCatalogValueCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}
}

/// @nodoc
mixin _$SkillSearchResult {


/// Create a copy of SkillSearchResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillSearchResultCopyWith<SkillSearchResult> get copyWith => _$SkillSearchResultCopyWithImpl<SkillSearchResult>(this as SkillSearchResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillSearchResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillSearchResult&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.catalogRevision, _this.catalogRevision) || other.catalogRevision == _this.catalogRevision)&&const DeepCollectionEquality().equals(other.matches, _this.matches)&&(identical(other.truncated, _this.truncated) || other.truncated == _this.truncated));
}


@override
int get hashCode {
  final _this = this as SkillSearchResult;
  return Object.hash(runtimeType,_this.projectId,_this.catalogRevision,const DeepCollectionEquality().hash(_this.matches),_this.truncated);
}



}

/// @nodoc
abstract mixin class $SkillSearchResultCopyWith<$Res>  {
  factory $SkillSearchResultCopyWith(SkillSearchResult value, $Res Function(SkillSearchResult) _then) = _$SkillSearchResultCopyWithImpl;
@useResult
$Res call({
 String projectId, int catalogRevision, List<SkillSummary> matches, bool truncated
});




}
/// @nodoc
class _$SkillSearchResultCopyWithImpl<$Res>
    implements $SkillSearchResultCopyWith<$Res> {
  _$SkillSearchResultCopyWithImpl(this._self, this._then);

  final SkillSearchResult _self;
  final $Res Function(SkillSearchResult) _then;

/// Create a copy of SkillSearchResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? catalogRevision = null,Object? matches = null,Object? truncated = null,}) {
  return _then(SkillSearchResult(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,catalogRevision: null == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int,matches: null == matches ? _self.matches : matches // ignore: cast_nullable_to_non_nullable
as List<SkillSummary>,truncated: null == truncated ? _self.truncated : truncated // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SkillSearchResult].
extension SkillSearchResultPatterns on SkillSearchResult {
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
