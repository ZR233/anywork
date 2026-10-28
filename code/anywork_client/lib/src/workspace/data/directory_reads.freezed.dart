// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'directory_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProjectDirectoryReadHeader {

 TypedListRef get projects;
/// Create a copy of ProjectDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryReadHeaderCopyWith<ProjectDirectoryReadHeader> get copyWith => _$ProjectDirectoryReadHeaderCopyWithImpl<ProjectDirectoryReadHeader>(this as ProjectDirectoryReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectDirectoryReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryReadHeader&&(identical(other.projects, _this.projects) || other.projects == _this.projects));
}


@override
int get hashCode {
  final _this = this as ProjectDirectoryReadHeader;
  return Object.hash(runtimeType,_this.projects);
}

@override
String toString() {
  final _this = this as ProjectDirectoryReadHeader;
  return 'ProjectDirectoryReadHeader(projects: ${_this.projects})';
}


}

/// @nodoc
abstract mixin class $ProjectDirectoryReadHeaderCopyWith<$Res>  {
  factory $ProjectDirectoryReadHeaderCopyWith(ProjectDirectoryReadHeader value, $Res Function(ProjectDirectoryReadHeader) _then) = _$ProjectDirectoryReadHeaderCopyWithImpl;
@useResult
$Res call({
 TypedListRef projects
});


$TypedListRefCopyWith<$Res> get projects;

}
/// @nodoc
class _$ProjectDirectoryReadHeaderCopyWithImpl<$Res>
    implements $ProjectDirectoryReadHeaderCopyWith<$Res> {
  _$ProjectDirectoryReadHeaderCopyWithImpl(this._self, this._then);

  final ProjectDirectoryReadHeader _self;
  final $Res Function(ProjectDirectoryReadHeader) _then;

/// Create a copy of ProjectDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projects = null,}) {
  return _then(ProjectDirectoryReadHeader(
projects: null == projects ? _self.projects : projects // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of ProjectDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get projects {

  return $TypedListRefCopyWith<$Res>(_self.projects, (value) {
    return _then(_self.copyWith(projects: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProjectDirectoryReadHeader].
extension ProjectDirectoryReadHeaderPatterns on ProjectDirectoryReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectDirectoryReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectDirectoryReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectDirectoryReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectDirectoryReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef projects)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectDirectoryReadHeader() when $default != null:
return $default(_that.projects);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef projects)  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryReadHeader():
return $default(_that.projects);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef projects)?  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryReadHeader() when $default != null:
return $default(_that.projects);case _:
  return null;

}
}

}

/// @nodoc


class _ProjectDirectoryReadHeader implements ProjectDirectoryReadHeader {
  const _ProjectDirectoryReadHeader({required this.projects});


@override final  TypedListRef projects;

/// Create a copy of ProjectDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectDirectoryReadHeaderCopyWith<_ProjectDirectoryReadHeader> get copyWith => __$ProjectDirectoryReadHeaderCopyWithImpl<_ProjectDirectoryReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectDirectoryReadHeader&&(identical(other.projects, projects) || other.projects == projects));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projects);
}

@override
String toString() {
    return 'ProjectDirectoryReadHeader(projects: $projects)';
}


}

/// @nodoc
abstract mixin class _$ProjectDirectoryReadHeaderCopyWith<$Res> implements $ProjectDirectoryReadHeaderCopyWith<$Res> {
  factory _$ProjectDirectoryReadHeaderCopyWith(_ProjectDirectoryReadHeader value, $Res Function(_ProjectDirectoryReadHeader) _then) = __$ProjectDirectoryReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef projects
});


@override $TypedListRefCopyWith<$Res> get projects;

}
/// @nodoc
class __$ProjectDirectoryReadHeaderCopyWithImpl<$Res>
    implements _$ProjectDirectoryReadHeaderCopyWith<$Res> {
  __$ProjectDirectoryReadHeaderCopyWithImpl(this._self, this._then);

  final _ProjectDirectoryReadHeader _self;
  final $Res Function(_ProjectDirectoryReadHeader) _then;

/// Create a copy of ProjectDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projects = null,}) {
  return _then(_ProjectDirectoryReadHeader(
projects: null == projects ? _self.projects : projects // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of ProjectDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get projects {

  return $TypedListRefCopyWith<$Res>(_self.projects, (value) {
    return _then(_self.copyWith(projects: value));
  });
}
}

/// @nodoc
mixin _$ThreadDirectoryReadHeader {

 TypedListRef get threads; ReadText? get nextCursor; bool get hasMore;
/// Create a copy of ThreadDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryReadHeaderCopyWith<ThreadDirectoryReadHeader> get copyWith => _$ThreadDirectoryReadHeaderCopyWithImpl<ThreadDirectoryReadHeader>(this as ThreadDirectoryReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadDirectoryReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryReadHeader&&(identical(other.threads, _this.threads) || other.threads == _this.threads)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor)&&(identical(other.hasMore, _this.hasMore) || other.hasMore == _this.hasMore));
}


@override
int get hashCode {
  final _this = this as ThreadDirectoryReadHeader;
  return Object.hash(runtimeType,_this.threads,_this.nextCursor,_this.hasMore);
}

@override
String toString() {
  final _this = this as ThreadDirectoryReadHeader;
  return 'ThreadDirectoryReadHeader(threads: ${_this.threads}, nextCursor: ${_this.nextCursor}, hasMore: ${_this.hasMore})';
}


}

/// @nodoc
abstract mixin class $ThreadDirectoryReadHeaderCopyWith<$Res>  {
  factory $ThreadDirectoryReadHeaderCopyWith(ThreadDirectoryReadHeader value, $Res Function(ThreadDirectoryReadHeader) _then) = _$ThreadDirectoryReadHeaderCopyWithImpl;
@useResult
$Res call({
 TypedListRef threads, ReadText? nextCursor, bool hasMore
});


$TypedListRefCopyWith<$Res> get threads;$ReadTextCopyWith<$Res>? get nextCursor;

}
/// @nodoc
class _$ThreadDirectoryReadHeaderCopyWithImpl<$Res>
    implements $ThreadDirectoryReadHeaderCopyWith<$Res> {
  _$ThreadDirectoryReadHeaderCopyWithImpl(this._self, this._then);

  final ThreadDirectoryReadHeader _self;
  final $Res Function(ThreadDirectoryReadHeader) _then;

/// Create a copy of ThreadDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threads = null,Object? nextCursor = freezed,Object? hasMore = null,}) {
  return _then(ThreadDirectoryReadHeader(
threads: null == threads ? _self.threads : threads // ignore: cast_nullable_to_non_nullable
as TypedListRef,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as ReadText?,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ThreadDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get threads {

  return $TypedListRefCopyWith<$Res>(_self.threads, (value) {
    return _then(_self.copyWith(threads: value));
  });
}/// Create a copy of ThreadDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get nextCursor {
    if (_self.nextCursor == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.nextCursor!, (value) {
    return _then(_self.copyWith(nextCursor: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadDirectoryReadHeader].
extension ThreadDirectoryReadHeaderPatterns on ThreadDirectoryReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadDirectoryReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadDirectoryReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadDirectoryReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadDirectoryReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef threads,  ReadText? nextCursor,  bool hasMore)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadDirectoryReadHeader() when $default != null:
return $default(_that.threads,_that.nextCursor,_that.hasMore);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef threads,  ReadText? nextCursor,  bool hasMore)  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryReadHeader():
return $default(_that.threads,_that.nextCursor,_that.hasMore);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef threads,  ReadText? nextCursor,  bool hasMore)?  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryReadHeader() when $default != null:
return $default(_that.threads,_that.nextCursor,_that.hasMore);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadDirectoryReadHeader implements ThreadDirectoryReadHeader {
  const _ThreadDirectoryReadHeader({required this.threads, required this.nextCursor, required this.hasMore});


@override final  TypedListRef threads;
@override final  ReadText? nextCursor;
@override final  bool hasMore;

/// Create a copy of ThreadDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadDirectoryReadHeaderCopyWith<_ThreadDirectoryReadHeader> get copyWith => __$ThreadDirectoryReadHeaderCopyWithImpl<_ThreadDirectoryReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadDirectoryReadHeader&&(identical(other.threads, threads) || other.threads == threads)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threads,nextCursor,hasMore);
}

@override
String toString() {
    return 'ThreadDirectoryReadHeader(threads: $threads, nextCursor: $nextCursor, hasMore: $hasMore)';
}


}

/// @nodoc
abstract mixin class _$ThreadDirectoryReadHeaderCopyWith<$Res> implements $ThreadDirectoryReadHeaderCopyWith<$Res> {
  factory _$ThreadDirectoryReadHeaderCopyWith(_ThreadDirectoryReadHeader value, $Res Function(_ThreadDirectoryReadHeader) _then) = __$ThreadDirectoryReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef threads, ReadText? nextCursor, bool hasMore
});


@override $TypedListRefCopyWith<$Res> get threads;@override $ReadTextCopyWith<$Res>? get nextCursor;

}
/// @nodoc
class __$ThreadDirectoryReadHeaderCopyWithImpl<$Res>
    implements _$ThreadDirectoryReadHeaderCopyWith<$Res> {
  __$ThreadDirectoryReadHeaderCopyWithImpl(this._self, this._then);

  final _ThreadDirectoryReadHeader _self;
  final $Res Function(_ThreadDirectoryReadHeader) _then;

/// Create a copy of ThreadDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threads = null,Object? nextCursor = freezed,Object? hasMore = null,}) {
  return _then(_ThreadDirectoryReadHeader(
threads: null == threads ? _self.threads : threads // ignore: cast_nullable_to_non_nullable
as TypedListRef,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as ReadText?,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ThreadDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get threads {

  return $TypedListRefCopyWith<$Res>(_self.threads, (value) {
    return _then(_self.copyWith(threads: value));
  });
}/// Create a copy of ThreadDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get nextCursor {
    if (_self.nextCursor == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.nextCursor!, (value) {
    return _then(_self.copyWith(nextCursor: value));
  });
}
}

/// @nodoc
mixin _$AgentDirectoryReadHeader {

 TypedListRef get agents;
/// Create a copy of AgentDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryReadHeaderCopyWith<AgentDirectoryReadHeader> get copyWith => _$AgentDirectoryReadHeaderCopyWithImpl<AgentDirectoryReadHeader>(this as AgentDirectoryReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryReadHeader&&(identical(other.agents, _this.agents) || other.agents == _this.agents));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryReadHeader;
  return Object.hash(runtimeType,_this.agents);
}

@override
String toString() {
  final _this = this as AgentDirectoryReadHeader;
  return 'AgentDirectoryReadHeader(agents: ${_this.agents})';
}


}

/// @nodoc
abstract mixin class $AgentDirectoryReadHeaderCopyWith<$Res>  {
  factory $AgentDirectoryReadHeaderCopyWith(AgentDirectoryReadHeader value, $Res Function(AgentDirectoryReadHeader) _then) = _$AgentDirectoryReadHeaderCopyWithImpl;
@useResult
$Res call({
 TypedListRef agents
});


$TypedListRefCopyWith<$Res> get agents;

}
/// @nodoc
class _$AgentDirectoryReadHeaderCopyWithImpl<$Res>
    implements $AgentDirectoryReadHeaderCopyWith<$Res> {
  _$AgentDirectoryReadHeaderCopyWithImpl(this._self, this._then);

  final AgentDirectoryReadHeader _self;
  final $Res Function(AgentDirectoryReadHeader) _then;

/// Create a copy of AgentDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? agents = null,}) {
  return _then(AgentDirectoryReadHeader(
agents: null == agents ? _self.agents : agents // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of AgentDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get agents {

  return $TypedListRefCopyWith<$Res>(_self.agents, (value) {
    return _then(_self.copyWith(agents: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentDirectoryReadHeader].
extension AgentDirectoryReadHeaderPatterns on AgentDirectoryReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentDirectoryReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentDirectoryReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentDirectoryReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentDirectoryReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef agents)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentDirectoryReadHeader() when $default != null:
return $default(_that.agents);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef agents)  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryReadHeader():
return $default(_that.agents);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef agents)?  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryReadHeader() when $default != null:
return $default(_that.agents);case _:
  return null;

}
}

}

/// @nodoc


class _AgentDirectoryReadHeader implements AgentDirectoryReadHeader {
  const _AgentDirectoryReadHeader({required this.agents});


@override final  TypedListRef agents;

/// Create a copy of AgentDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentDirectoryReadHeaderCopyWith<_AgentDirectoryReadHeader> get copyWith => __$AgentDirectoryReadHeaderCopyWithImpl<_AgentDirectoryReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentDirectoryReadHeader&&(identical(other.agents, agents) || other.agents == agents));
}


@override
int get hashCode {
    return Object.hash(runtimeType,agents);
}

@override
String toString() {
    return 'AgentDirectoryReadHeader(agents: $agents)';
}


}

/// @nodoc
abstract mixin class _$AgentDirectoryReadHeaderCopyWith<$Res> implements $AgentDirectoryReadHeaderCopyWith<$Res> {
  factory _$AgentDirectoryReadHeaderCopyWith(_AgentDirectoryReadHeader value, $Res Function(_AgentDirectoryReadHeader) _then) = __$AgentDirectoryReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef agents
});


@override $TypedListRefCopyWith<$Res> get agents;

}
/// @nodoc
class __$AgentDirectoryReadHeaderCopyWithImpl<$Res>
    implements _$AgentDirectoryReadHeaderCopyWith<$Res> {
  __$AgentDirectoryReadHeaderCopyWithImpl(this._self, this._then);

  final _AgentDirectoryReadHeader _self;
  final $Res Function(_AgentDirectoryReadHeader) _then;

/// Create a copy of AgentDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? agents = null,}) {
  return _then(_AgentDirectoryReadHeader(
agents: null == agents ? _self.agents : agents // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of AgentDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get agents {

  return $TypedListRefCopyWith<$Res>(_self.agents, (value) {
    return _then(_self.copyWith(agents: value));
  });
}
}

/// @nodoc
mixin _$ProjectRecordRead {

 ReadText get id; ReadText get name; ReadText get path; ReadText? get sshAlias; int get updatedAt;
/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectRecordReadCopyWith<ProjectRecordRead> get copyWith => _$ProjectRecordReadCopyWithImpl<ProjectRecordRead>(this as ProjectRecordRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectRecordRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectRecordRead&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.sshAlias, _this.sshAlias) || other.sshAlias == _this.sshAlias)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as ProjectRecordRead;
  return Object.hash(runtimeType,_this.id,_this.name,_this.path,_this.sshAlias,_this.updatedAt);
}



}

/// @nodoc
abstract mixin class $ProjectRecordReadCopyWith<$Res>  {
  factory $ProjectRecordReadCopyWith(ProjectRecordRead value, $Res Function(ProjectRecordRead) _then) = _$ProjectRecordReadCopyWithImpl;
@useResult
$Res call({
 ReadText id, ReadText name, ReadText path, ReadText? sshAlias, int updatedAt
});


$ReadTextCopyWith<$Res> get id;$ReadTextCopyWith<$Res> get name;$ReadTextCopyWith<$Res> get path;$ReadTextCopyWith<$Res>? get sshAlias;

}
/// @nodoc
class _$ProjectRecordReadCopyWithImpl<$Res>
    implements $ProjectRecordReadCopyWith<$Res> {
  _$ProjectRecordReadCopyWithImpl(this._self, this._then);

  final ProjectRecordRead _self;
  final $Res Function(ProjectRecordRead) _then;

/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? path = null,Object? sshAlias = freezed,Object? updatedAt = null,}) {
  return _then(ProjectRecordRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,sshAlias: freezed == sshAlias ? _self.sshAlias : sshAlias // ignore: cast_nullable_to_non_nullable
as ReadText?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get sshAlias {
    if (_self.sshAlias == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.sshAlias!, (value) {
    return _then(_self.copyWith(sshAlias: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProjectRecordRead].
extension ProjectRecordReadPatterns on ProjectRecordRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectRecordRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectRecordRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectRecordRead value)  $default,){
final _that = this;
switch (_that) {
case _ProjectRecordRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectRecordRead value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectRecordRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText id,  ReadText name,  ReadText path,  ReadText? sshAlias,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectRecordRead() when $default != null:
return $default(_that.id,_that.name,_that.path,_that.sshAlias,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText id,  ReadText name,  ReadText path,  ReadText? sshAlias,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _ProjectRecordRead():
return $default(_that.id,_that.name,_that.path,_that.sshAlias,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText id,  ReadText name,  ReadText path,  ReadText? sshAlias,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _ProjectRecordRead() when $default != null:
return $default(_that.id,_that.name,_that.path,_that.sshAlias,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _ProjectRecordRead implements ProjectRecordRead {
  const _ProjectRecordRead({required this.id, required this.name, required this.path, required this.sshAlias, required this.updatedAt});


@override final  ReadText id;
@override final  ReadText name;
@override final  ReadText path;
@override final  ReadText? sshAlias;
@override final  int updatedAt;

/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectRecordReadCopyWith<_ProjectRecordRead> get copyWith => __$ProjectRecordReadCopyWithImpl<_ProjectRecordRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectRecordRead&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.path, path) || other.path == path)&&(identical(other.sshAlias, sshAlias) || other.sshAlias == sshAlias)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,path,sshAlias,updatedAt);
}



}

/// @nodoc
abstract mixin class _$ProjectRecordReadCopyWith<$Res> implements $ProjectRecordReadCopyWith<$Res> {
  factory _$ProjectRecordReadCopyWith(_ProjectRecordRead value, $Res Function(_ProjectRecordRead) _then) = __$ProjectRecordReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText id, ReadText name, ReadText path, ReadText? sshAlias, int updatedAt
});


@override $ReadTextCopyWith<$Res> get id;@override $ReadTextCopyWith<$Res> get name;@override $ReadTextCopyWith<$Res> get path;@override $ReadTextCopyWith<$Res>? get sshAlias;

}
/// @nodoc
class __$ProjectRecordReadCopyWithImpl<$Res>
    implements _$ProjectRecordReadCopyWith<$Res> {
  __$ProjectRecordReadCopyWithImpl(this._self, this._then);

  final _ProjectRecordRead _self;
  final $Res Function(_ProjectRecordRead) _then;

/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? path = null,Object? sshAlias = freezed,Object? updatedAt = null,}) {
  return _then(_ProjectRecordRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,sshAlias: freezed == sshAlias ? _self.sshAlias : sshAlias // ignore: cast_nullable_to_non_nullable
as ReadText?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of ProjectRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get sshAlias {
    if (_self.sshAlias == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.sshAlias!, (value) {
    return _then(_self.copyWith(sshAlias: value));
  });
}
}

/// @nodoc
mixin _$WorkspaceThreadRecordRead {

 ReadText get id; ReadText get projectId; ReadText get title; ReadText get mode; ThreadWorkspaceMode get workspaceMode; DelegationMode get delegationMode; DelegationPreference get delegationPreference; FrozenModelSelectionRead? get frozenModel; ReadText get workspacePath; ReadText get rootThreadId; ReadText? get parentThreadId; ReadText get role; ReadText get agentPath; ThreadStatus get status; int get createdAt; int get updatedAt; int? get lastUserMessageAt; bool get archived;
/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordReadCopyWith<WorkspaceThreadRecordRead> get copyWith => _$WorkspaceThreadRecordReadCopyWithImpl<WorkspaceThreadRecordRead>(this as WorkspaceThreadRecordRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceThreadRecordRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceThreadRecordRead&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.workspaceMode, _this.workspaceMode) || other.workspaceMode == _this.workspaceMode)&&(identical(other.delegationMode, _this.delegationMode) || other.delegationMode == _this.delegationMode)&&(identical(other.delegationPreference, _this.delegationPreference) || other.delegationPreference == _this.delegationPreference)&&(identical(other.frozenModel, _this.frozenModel) || other.frozenModel == _this.frozenModel)&&(identical(other.workspacePath, _this.workspacePath) || other.workspacePath == _this.workspacePath)&&(identical(other.rootThreadId, _this.rootThreadId) || other.rootThreadId == _this.rootThreadId)&&(identical(other.parentThreadId, _this.parentThreadId) || other.parentThreadId == _this.parentThreadId)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.agentPath, _this.agentPath) || other.agentPath == _this.agentPath)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.lastUserMessageAt, _this.lastUserMessageAt) || other.lastUserMessageAt == _this.lastUserMessageAt)&&(identical(other.archived, _this.archived) || other.archived == _this.archived));
}


@override
int get hashCode {
  final _this = this as WorkspaceThreadRecordRead;
  return Object.hash(runtimeType,_this.id,_this.projectId,_this.title,_this.mode,_this.workspaceMode,_this.delegationMode,_this.delegationPreference,_this.frozenModel,_this.workspacePath,_this.rootThreadId,_this.parentThreadId,_this.role,_this.agentPath,_this.status,_this.createdAt,_this.updatedAt,_this.lastUserMessageAt,_this.archived);
}



}

/// @nodoc
abstract mixin class $WorkspaceThreadRecordReadCopyWith<$Res>  {
  factory $WorkspaceThreadRecordReadCopyWith(WorkspaceThreadRecordRead value, $Res Function(WorkspaceThreadRecordRead) _then) = _$WorkspaceThreadRecordReadCopyWithImpl;
@useResult
$Res call({
 ReadText id, ReadText projectId, ReadText title, ReadText mode, ThreadWorkspaceMode workspaceMode, DelegationMode delegationMode, DelegationPreference delegationPreference, FrozenModelSelectionRead? frozenModel, ReadText workspacePath, ReadText rootThreadId, ReadText? parentThreadId, ReadText role, ReadText agentPath, ThreadStatus status, int createdAt, int updatedAt, int? lastUserMessageAt, bool archived
});


$ReadTextCopyWith<$Res> get id;$ReadTextCopyWith<$Res> get projectId;$ReadTextCopyWith<$Res> get title;$ReadTextCopyWith<$Res> get mode;$FrozenModelSelectionReadCopyWith<$Res>? get frozenModel;$ReadTextCopyWith<$Res> get workspacePath;$ReadTextCopyWith<$Res> get rootThreadId;$ReadTextCopyWith<$Res>? get parentThreadId;$ReadTextCopyWith<$Res> get role;$ReadTextCopyWith<$Res> get agentPath;

}
/// @nodoc
class _$WorkspaceThreadRecordReadCopyWithImpl<$Res>
    implements $WorkspaceThreadRecordReadCopyWith<$Res> {
  _$WorkspaceThreadRecordReadCopyWithImpl(this._self, this._then);

  final WorkspaceThreadRecordRead _self;
  final $Res Function(WorkspaceThreadRecordRead) _then;

/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? projectId = null,Object? title = null,Object? mode = null,Object? workspaceMode = null,Object? delegationMode = null,Object? delegationPreference = null,Object? frozenModel = freezed,Object? workspacePath = null,Object? rootThreadId = null,Object? parentThreadId = freezed,Object? role = null,Object? agentPath = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,Object? lastUserMessageAt = freezed,Object? archived = null,}) {
  return _then(WorkspaceThreadRecordRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as ReadText,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as ReadText,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ReadText,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as ThreadWorkspaceMode,delegationMode: null == delegationMode ? _self.delegationMode : delegationMode // ignore: cast_nullable_to_non_nullable
as DelegationMode,delegationPreference: null == delegationPreference ? _self.delegationPreference : delegationPreference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,frozenModel: freezed == frozenModel ? _self.frozenModel : frozenModel // ignore: cast_nullable_to_non_nullable
as FrozenModelSelectionRead?,workspacePath: null == workspacePath ? _self.workspacePath : workspacePath // ignore: cast_nullable_to_non_nullable
as ReadText,rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as ReadText,parentThreadId: freezed == parentThreadId ? _self.parentThreadId : parentThreadId // ignore: cast_nullable_to_non_nullable
as ReadText?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ReadText,agentPath: null == agentPath ? _self.agentPath : agentPath // ignore: cast_nullable_to_non_nullable
as ReadText,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastUserMessageAt: freezed == lastUserMessageAt ? _self.lastUserMessageAt : lastUserMessageAt // ignore: cast_nullable_to_non_nullable
as int?,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get projectId {

  return $ReadTextCopyWith<$Res>(_self.projectId, (value) {
    return _then(_self.copyWith(projectId: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get title {

  return $ReadTextCopyWith<$Res>(_self.title, (value) {
    return _then(_self.copyWith(title: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get mode {

  return $ReadTextCopyWith<$Res>(_self.mode, (value) {
    return _then(_self.copyWith(mode: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FrozenModelSelectionReadCopyWith<$Res>? get frozenModel {
    if (_self.frozenModel == null) {
    return null;
  }

  return $FrozenModelSelectionReadCopyWith<$Res>(_self.frozenModel!, (value) {
    return _then(_self.copyWith(frozenModel: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get workspacePath {

  return $ReadTextCopyWith<$Res>(_self.workspacePath, (value) {
    return _then(_self.copyWith(workspacePath: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get rootThreadId {

  return $ReadTextCopyWith<$Res>(_self.rootThreadId, (value) {
    return _then(_self.copyWith(rootThreadId: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get parentThreadId {
    if (_self.parentThreadId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.parentThreadId!, (value) {
    return _then(_self.copyWith(parentThreadId: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get role {

  return $ReadTextCopyWith<$Res>(_self.role, (value) {
    return _then(_self.copyWith(role: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get agentPath {

  return $ReadTextCopyWith<$Res>(_self.agentPath, (value) {
    return _then(_self.copyWith(agentPath: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkspaceThreadRecordRead].
extension WorkspaceThreadRecordReadPatterns on WorkspaceThreadRecordRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceThreadRecordRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceThreadRecordRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceThreadRecordRead value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceThreadRecordRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceThreadRecordRead value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceThreadRecordRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText id,  ReadText projectId,  ReadText title,  ReadText mode,  ThreadWorkspaceMode workspaceMode,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  FrozenModelSelectionRead? frozenModel,  ReadText workspacePath,  ReadText rootThreadId,  ReadText? parentThreadId,  ReadText role,  ReadText agentPath,  ThreadStatus status,  int createdAt,  int updatedAt,  int? lastUserMessageAt,  bool archived)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceThreadRecordRead() when $default != null:
return $default(_that.id,_that.projectId,_that.title,_that.mode,_that.workspaceMode,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.workspacePath,_that.rootThreadId,_that.parentThreadId,_that.role,_that.agentPath,_that.status,_that.createdAt,_that.updatedAt,_that.lastUserMessageAt,_that.archived);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText id,  ReadText projectId,  ReadText title,  ReadText mode,  ThreadWorkspaceMode workspaceMode,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  FrozenModelSelectionRead? frozenModel,  ReadText workspacePath,  ReadText rootThreadId,  ReadText? parentThreadId,  ReadText role,  ReadText agentPath,  ThreadStatus status,  int createdAt,  int updatedAt,  int? lastUserMessageAt,  bool archived)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceThreadRecordRead():
return $default(_that.id,_that.projectId,_that.title,_that.mode,_that.workspaceMode,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.workspacePath,_that.rootThreadId,_that.parentThreadId,_that.role,_that.agentPath,_that.status,_that.createdAt,_that.updatedAt,_that.lastUserMessageAt,_that.archived);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText id,  ReadText projectId,  ReadText title,  ReadText mode,  ThreadWorkspaceMode workspaceMode,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  FrozenModelSelectionRead? frozenModel,  ReadText workspacePath,  ReadText rootThreadId,  ReadText? parentThreadId,  ReadText role,  ReadText agentPath,  ThreadStatus status,  int createdAt,  int updatedAt,  int? lastUserMessageAt,  bool archived)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceThreadRecordRead() when $default != null:
return $default(_that.id,_that.projectId,_that.title,_that.mode,_that.workspaceMode,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.workspacePath,_that.rootThreadId,_that.parentThreadId,_that.role,_that.agentPath,_that.status,_that.createdAt,_that.updatedAt,_that.lastUserMessageAt,_that.archived);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceThreadRecordRead implements WorkspaceThreadRecordRead {
  const _WorkspaceThreadRecordRead({required this.id, required this.projectId, required this.title, required this.mode, required this.workspaceMode, required this.delegationMode, required this.delegationPreference, required this.frozenModel, required this.workspacePath, required this.rootThreadId, required this.parentThreadId, required this.role, required this.agentPath, required this.status, required this.createdAt, required this.updatedAt, required this.lastUserMessageAt, required this.archived});


@override final  ReadText id;
@override final  ReadText projectId;
@override final  ReadText title;
@override final  ReadText mode;
@override final  ThreadWorkspaceMode workspaceMode;
@override final  DelegationMode delegationMode;
@override final  DelegationPreference delegationPreference;
@override final  FrozenModelSelectionRead? frozenModel;
@override final  ReadText workspacePath;
@override final  ReadText rootThreadId;
@override final  ReadText? parentThreadId;
@override final  ReadText role;
@override final  ReadText agentPath;
@override final  ThreadStatus status;
@override final  int createdAt;
@override final  int updatedAt;
@override final  int? lastUserMessageAt;
@override final  bool archived;

/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceThreadRecordReadCopyWith<_WorkspaceThreadRecordRead> get copyWith => __$WorkspaceThreadRecordReadCopyWithImpl<_WorkspaceThreadRecordRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceThreadRecordRead&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.title, title) || other.title == title)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode)&&(identical(other.delegationMode, delegationMode) || other.delegationMode == delegationMode)&&(identical(other.delegationPreference, delegationPreference) || other.delegationPreference == delegationPreference)&&(identical(other.frozenModel, frozenModel) || other.frozenModel == frozenModel)&&(identical(other.workspacePath, workspacePath) || other.workspacePath == workspacePath)&&(identical(other.rootThreadId, rootThreadId) || other.rootThreadId == rootThreadId)&&(identical(other.parentThreadId, parentThreadId) || other.parentThreadId == parentThreadId)&&(identical(other.role, role) || other.role == role)&&(identical(other.agentPath, agentPath) || other.agentPath == agentPath)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastUserMessageAt, lastUserMessageAt) || other.lastUserMessageAt == lastUserMessageAt)&&(identical(other.archived, archived) || other.archived == archived));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,projectId,title,mode,workspaceMode,delegationMode,delegationPreference,frozenModel,workspacePath,rootThreadId,parentThreadId,role,agentPath,status,createdAt,updatedAt,lastUserMessageAt,archived);
}



}

/// @nodoc
abstract mixin class _$WorkspaceThreadRecordReadCopyWith<$Res> implements $WorkspaceThreadRecordReadCopyWith<$Res> {
  factory _$WorkspaceThreadRecordReadCopyWith(_WorkspaceThreadRecordRead value, $Res Function(_WorkspaceThreadRecordRead) _then) = __$WorkspaceThreadRecordReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText id, ReadText projectId, ReadText title, ReadText mode, ThreadWorkspaceMode workspaceMode, DelegationMode delegationMode, DelegationPreference delegationPreference, FrozenModelSelectionRead? frozenModel, ReadText workspacePath, ReadText rootThreadId, ReadText? parentThreadId, ReadText role, ReadText agentPath, ThreadStatus status, int createdAt, int updatedAt, int? lastUserMessageAt, bool archived
});


@override $ReadTextCopyWith<$Res> get id;@override $ReadTextCopyWith<$Res> get projectId;@override $ReadTextCopyWith<$Res> get title;@override $ReadTextCopyWith<$Res> get mode;@override $FrozenModelSelectionReadCopyWith<$Res>? get frozenModel;@override $ReadTextCopyWith<$Res> get workspacePath;@override $ReadTextCopyWith<$Res> get rootThreadId;@override $ReadTextCopyWith<$Res>? get parentThreadId;@override $ReadTextCopyWith<$Res> get role;@override $ReadTextCopyWith<$Res> get agentPath;

}
/// @nodoc
class __$WorkspaceThreadRecordReadCopyWithImpl<$Res>
    implements _$WorkspaceThreadRecordReadCopyWith<$Res> {
  __$WorkspaceThreadRecordReadCopyWithImpl(this._self, this._then);

  final _WorkspaceThreadRecordRead _self;
  final $Res Function(_WorkspaceThreadRecordRead) _then;

/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? projectId = null,Object? title = null,Object? mode = null,Object? workspaceMode = null,Object? delegationMode = null,Object? delegationPreference = null,Object? frozenModel = freezed,Object? workspacePath = null,Object? rootThreadId = null,Object? parentThreadId = freezed,Object? role = null,Object? agentPath = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,Object? lastUserMessageAt = freezed,Object? archived = null,}) {
  return _then(_WorkspaceThreadRecordRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as ReadText,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as ReadText,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ReadText,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as ThreadWorkspaceMode,delegationMode: null == delegationMode ? _self.delegationMode : delegationMode // ignore: cast_nullable_to_non_nullable
as DelegationMode,delegationPreference: null == delegationPreference ? _self.delegationPreference : delegationPreference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,frozenModel: freezed == frozenModel ? _self.frozenModel : frozenModel // ignore: cast_nullable_to_non_nullable
as FrozenModelSelectionRead?,workspacePath: null == workspacePath ? _self.workspacePath : workspacePath // ignore: cast_nullable_to_non_nullable
as ReadText,rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as ReadText,parentThreadId: freezed == parentThreadId ? _self.parentThreadId : parentThreadId // ignore: cast_nullable_to_non_nullable
as ReadText?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ReadText,agentPath: null == agentPath ? _self.agentPath : agentPath // ignore: cast_nullable_to_non_nullable
as ReadText,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastUserMessageAt: freezed == lastUserMessageAt ? _self.lastUserMessageAt : lastUserMessageAt // ignore: cast_nullable_to_non_nullable
as int?,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get projectId {

  return $ReadTextCopyWith<$Res>(_self.projectId, (value) {
    return _then(_self.copyWith(projectId: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get title {

  return $ReadTextCopyWith<$Res>(_self.title, (value) {
    return _then(_self.copyWith(title: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get mode {

  return $ReadTextCopyWith<$Res>(_self.mode, (value) {
    return _then(_self.copyWith(mode: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FrozenModelSelectionReadCopyWith<$Res>? get frozenModel {
    if (_self.frozenModel == null) {
    return null;
  }

  return $FrozenModelSelectionReadCopyWith<$Res>(_self.frozenModel!, (value) {
    return _then(_self.copyWith(frozenModel: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get workspacePath {

  return $ReadTextCopyWith<$Res>(_self.workspacePath, (value) {
    return _then(_self.copyWith(workspacePath: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get rootThreadId {

  return $ReadTextCopyWith<$Res>(_self.rootThreadId, (value) {
    return _then(_self.copyWith(rootThreadId: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get parentThreadId {
    if (_self.parentThreadId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.parentThreadId!, (value) {
    return _then(_self.copyWith(parentThreadId: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get role {

  return $ReadTextCopyWith<$Res>(_self.role, (value) {
    return _then(_self.copyWith(role: value));
  });
}/// Create a copy of WorkspaceThreadRecordRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get agentPath {

  return $ReadTextCopyWith<$Res>(_self.agentPath, (value) {
    return _then(_self.copyWith(agentPath: value));
  });
}
}

/// @nodoc
mixin _$AgentBudgetPauseRead {

 ReadText get turnId; BudgetLimitSnapshot get limit; int get pausedAt;
/// Create a copy of AgentBudgetPauseRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentBudgetPauseReadCopyWith<AgentBudgetPauseRead> get copyWith => _$AgentBudgetPauseReadCopyWithImpl<AgentBudgetPauseRead>(this as AgentBudgetPauseRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentBudgetPauseRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentBudgetPauseRead&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId)&&(identical(other.limit, _this.limit) || other.limit == _this.limit)&&(identical(other.pausedAt, _this.pausedAt) || other.pausedAt == _this.pausedAt));
}


@override
int get hashCode {
  final _this = this as AgentBudgetPauseRead;
  return Object.hash(runtimeType,_this.turnId,_this.limit,_this.pausedAt);
}



}

/// @nodoc
abstract mixin class $AgentBudgetPauseReadCopyWith<$Res>  {
  factory $AgentBudgetPauseReadCopyWith(AgentBudgetPauseRead value, $Res Function(AgentBudgetPauseRead) _then) = _$AgentBudgetPauseReadCopyWithImpl;
@useResult
$Res call({
 ReadText turnId, BudgetLimitSnapshot limit, int pausedAt
});


$ReadTextCopyWith<$Res> get turnId;$BudgetLimitSnapshotCopyWith<$Res> get limit;

}
/// @nodoc
class _$AgentBudgetPauseReadCopyWithImpl<$Res>
    implements $AgentBudgetPauseReadCopyWith<$Res> {
  _$AgentBudgetPauseReadCopyWithImpl(this._self, this._then);

  final AgentBudgetPauseRead _self;
  final $Res Function(AgentBudgetPauseRead) _then;

/// Create a copy of AgentBudgetPauseRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? turnId = null,Object? limit = null,Object? pausedAt = null,}) {
  return _then(AgentBudgetPauseRead(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as BudgetLimitSnapshot,pausedAt: null == pausedAt ? _self.pausedAt : pausedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AgentBudgetPauseRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of AgentBudgetPauseRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BudgetLimitSnapshotCopyWith<$Res> get limit {

  return $BudgetLimitSnapshotCopyWith<$Res>(_self.limit, (value) {
    return _then(_self.copyWith(limit: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentBudgetPauseRead].
extension AgentBudgetPauseReadPatterns on AgentBudgetPauseRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentBudgetPauseRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentBudgetPauseRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentBudgetPauseRead value)  $default,){
final _that = this;
switch (_that) {
case _AgentBudgetPauseRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentBudgetPauseRead value)?  $default,){
final _that = this;
switch (_that) {
case _AgentBudgetPauseRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText turnId,  BudgetLimitSnapshot limit,  int pausedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentBudgetPauseRead() when $default != null:
return $default(_that.turnId,_that.limit,_that.pausedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText turnId,  BudgetLimitSnapshot limit,  int pausedAt)  $default,) {final _that = this;
switch (_that) {
case _AgentBudgetPauseRead():
return $default(_that.turnId,_that.limit,_that.pausedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText turnId,  BudgetLimitSnapshot limit,  int pausedAt)?  $default,) {final _that = this;
switch (_that) {
case _AgentBudgetPauseRead() when $default != null:
return $default(_that.turnId,_that.limit,_that.pausedAt);case _:
  return null;

}
}

}

/// @nodoc


class _AgentBudgetPauseRead implements AgentBudgetPauseRead {
  const _AgentBudgetPauseRead({required this.turnId, required this.limit, required this.pausedAt});


@override final  ReadText turnId;
@override final  BudgetLimitSnapshot limit;
@override final  int pausedAt;

/// Create a copy of AgentBudgetPauseRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentBudgetPauseReadCopyWith<_AgentBudgetPauseRead> get copyWith => __$AgentBudgetPauseReadCopyWithImpl<_AgentBudgetPauseRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentBudgetPauseRead&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.limit, limit) || other.limit == limit)&&(identical(other.pausedAt, pausedAt) || other.pausedAt == pausedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId,limit,pausedAt);
}



}

/// @nodoc
abstract mixin class _$AgentBudgetPauseReadCopyWith<$Res> implements $AgentBudgetPauseReadCopyWith<$Res> {
  factory _$AgentBudgetPauseReadCopyWith(_AgentBudgetPauseRead value, $Res Function(_AgentBudgetPauseRead) _then) = __$AgentBudgetPauseReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText turnId, BudgetLimitSnapshot limit, int pausedAt
});


@override $ReadTextCopyWith<$Res> get turnId;@override $BudgetLimitSnapshotCopyWith<$Res> get limit;

}
/// @nodoc
class __$AgentBudgetPauseReadCopyWithImpl<$Res>
    implements _$AgentBudgetPauseReadCopyWith<$Res> {
  __$AgentBudgetPauseReadCopyWithImpl(this._self, this._then);

  final _AgentBudgetPauseRead _self;
  final $Res Function(_AgentBudgetPauseRead) _then;

/// Create a copy of AgentBudgetPauseRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? turnId = null,Object? limit = null,Object? pausedAt = null,}) {
  return _then(_AgentBudgetPauseRead(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as BudgetLimitSnapshot,pausedAt: null == pausedAt ? _self.pausedAt : pausedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AgentBudgetPauseRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of AgentBudgetPauseRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BudgetLimitSnapshotCopyWith<$Res> get limit {

  return $BudgetLimitSnapshotCopyWith<$Res>(_self.limit, (value) {
    return _then(_self.copyWith(limit: value));
  });
}
}

/// @nodoc
mixin _$AgentStateRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentStateRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AgentStateReadCopyWith<$Res>  {
$AgentStateReadCopyWith(AgentStateRead _, $Res Function(AgentStateRead) __);
}


/// Adds pattern-matching-related methods to [AgentStateRead].
extension AgentStateReadPatterns on AgentStateRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IdleAgentStateRead value)?  idle,TResult Function( QueuedAgentStateRead value)?  queued,TResult Function( RunningAgentStateRead value)?  running,TResult Function( WaitingToolAgentStateRead value)?  waitingTool,TResult Function( WaitingInteractionAgentStateRead value)?  waitingInteraction,TResult Function( CancellingAgentStateRead value)?  cancelling,TResult Function( ClosingAgentStateRead value)?  closing,TResult Function( ClosedAgentStateRead value)?  closed,TResult Function( FaultedAgentStateRead value)?  faulted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IdleAgentStateRead() when idle != null:
return idle(_that);case QueuedAgentStateRead() when queued != null:
return queued(_that);case RunningAgentStateRead() when running != null:
return running(_that);case WaitingToolAgentStateRead() when waitingTool != null:
return waitingTool(_that);case WaitingInteractionAgentStateRead() when waitingInteraction != null:
return waitingInteraction(_that);case CancellingAgentStateRead() when cancelling != null:
return cancelling(_that);case ClosingAgentStateRead() when closing != null:
return closing(_that);case ClosedAgentStateRead() when closed != null:
return closed(_that);case FaultedAgentStateRead() when faulted != null:
return faulted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IdleAgentStateRead value)  idle,required TResult Function( QueuedAgentStateRead value)  queued,required TResult Function( RunningAgentStateRead value)  running,required TResult Function( WaitingToolAgentStateRead value)  waitingTool,required TResult Function( WaitingInteractionAgentStateRead value)  waitingInteraction,required TResult Function( CancellingAgentStateRead value)  cancelling,required TResult Function( ClosingAgentStateRead value)  closing,required TResult Function( ClosedAgentStateRead value)  closed,required TResult Function( FaultedAgentStateRead value)  faulted,}){
final _that = this;
switch (_that) {
case IdleAgentStateRead():
return idle(_that);case QueuedAgentStateRead():
return queued(_that);case RunningAgentStateRead():
return running(_that);case WaitingToolAgentStateRead():
return waitingTool(_that);case WaitingInteractionAgentStateRead():
return waitingInteraction(_that);case CancellingAgentStateRead():
return cancelling(_that);case ClosingAgentStateRead():
return closing(_that);case ClosedAgentStateRead():
return closed(_that);case FaultedAgentStateRead():
return faulted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IdleAgentStateRead value)?  idle,TResult? Function( QueuedAgentStateRead value)?  queued,TResult? Function( RunningAgentStateRead value)?  running,TResult? Function( WaitingToolAgentStateRead value)?  waitingTool,TResult? Function( WaitingInteractionAgentStateRead value)?  waitingInteraction,TResult? Function( CancellingAgentStateRead value)?  cancelling,TResult? Function( ClosingAgentStateRead value)?  closing,TResult? Function( ClosedAgentStateRead value)?  closed,TResult? Function( FaultedAgentStateRead value)?  faulted,}){
final _that = this;
switch (_that) {
case IdleAgentStateRead() when idle != null:
return idle(_that);case QueuedAgentStateRead() when queued != null:
return queued(_that);case RunningAgentStateRead() when running != null:
return running(_that);case WaitingToolAgentStateRead() when waitingTool != null:
return waitingTool(_that);case WaitingInteractionAgentStateRead() when waitingInteraction != null:
return waitingInteraction(_that);case CancellingAgentStateRead() when cancelling != null:
return cancelling(_that);case ClosingAgentStateRead() when closing != null:
return closing(_that);case ClosedAgentStateRead() when closed != null:
return closed(_that);case FaultedAgentStateRead() when faulted != null:
return faulted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( AgentBudgetPauseRead? budgetPause)?  idle,TResult Function( ReadText turnId)?  queued,TResult Function( ReadText turnId)?  running,TResult Function( ReadText turnId)?  waitingTool,TResult Function( ReadText turnId,  ReadText interactionId)?  waitingInteraction,TResult Function( ReadText turnId)?  cancelling,TResult Function( AgentWorkspaceDisposition workspaceDisposition,  ReadText? turnId,  SourceStateErrorRead? error)?  closing,TResult Function()?  closed,TResult Function( SourceStateErrorRead error,  ReadText? turnId,  AgentFaultClassification classification)?  faulted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IdleAgentStateRead() when idle != null:
return idle(_that.budgetPause);case QueuedAgentStateRead() when queued != null:
return queued(_that.turnId);case RunningAgentStateRead() when running != null:
return running(_that.turnId);case WaitingToolAgentStateRead() when waitingTool != null:
return waitingTool(_that.turnId);case WaitingInteractionAgentStateRead() when waitingInteraction != null:
return waitingInteraction(_that.turnId,_that.interactionId);case CancellingAgentStateRead() when cancelling != null:
return cancelling(_that.turnId);case ClosingAgentStateRead() when closing != null:
return closing(_that.workspaceDisposition,_that.turnId,_that.error);case ClosedAgentStateRead() when closed != null:
return closed();case FaultedAgentStateRead() when faulted != null:
return faulted(_that.error,_that.turnId,_that.classification);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( AgentBudgetPauseRead? budgetPause)  idle,required TResult Function( ReadText turnId)  queued,required TResult Function( ReadText turnId)  running,required TResult Function( ReadText turnId)  waitingTool,required TResult Function( ReadText turnId,  ReadText interactionId)  waitingInteraction,required TResult Function( ReadText turnId)  cancelling,required TResult Function( AgentWorkspaceDisposition workspaceDisposition,  ReadText? turnId,  SourceStateErrorRead? error)  closing,required TResult Function()  closed,required TResult Function( SourceStateErrorRead error,  ReadText? turnId,  AgentFaultClassification classification)  faulted,}) {final _that = this;
switch (_that) {
case IdleAgentStateRead():
return idle(_that.budgetPause);case QueuedAgentStateRead():
return queued(_that.turnId);case RunningAgentStateRead():
return running(_that.turnId);case WaitingToolAgentStateRead():
return waitingTool(_that.turnId);case WaitingInteractionAgentStateRead():
return waitingInteraction(_that.turnId,_that.interactionId);case CancellingAgentStateRead():
return cancelling(_that.turnId);case ClosingAgentStateRead():
return closing(_that.workspaceDisposition,_that.turnId,_that.error);case ClosedAgentStateRead():
return closed();case FaultedAgentStateRead():
return faulted(_that.error,_that.turnId,_that.classification);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( AgentBudgetPauseRead? budgetPause)?  idle,TResult? Function( ReadText turnId)?  queued,TResult? Function( ReadText turnId)?  running,TResult? Function( ReadText turnId)?  waitingTool,TResult? Function( ReadText turnId,  ReadText interactionId)?  waitingInteraction,TResult? Function( ReadText turnId)?  cancelling,TResult? Function( AgentWorkspaceDisposition workspaceDisposition,  ReadText? turnId,  SourceStateErrorRead? error)?  closing,TResult? Function()?  closed,TResult? Function( SourceStateErrorRead error,  ReadText? turnId,  AgentFaultClassification classification)?  faulted,}) {final _that = this;
switch (_that) {
case IdleAgentStateRead() when idle != null:
return idle(_that.budgetPause);case QueuedAgentStateRead() when queued != null:
return queued(_that.turnId);case RunningAgentStateRead() when running != null:
return running(_that.turnId);case WaitingToolAgentStateRead() when waitingTool != null:
return waitingTool(_that.turnId);case WaitingInteractionAgentStateRead() when waitingInteraction != null:
return waitingInteraction(_that.turnId,_that.interactionId);case CancellingAgentStateRead() when cancelling != null:
return cancelling(_that.turnId);case ClosingAgentStateRead() when closing != null:
return closing(_that.workspaceDisposition,_that.turnId,_that.error);case ClosedAgentStateRead() when closed != null:
return closed();case FaultedAgentStateRead() when faulted != null:
return faulted(_that.error,_that.turnId,_that.classification);case _:
  return null;

}
}

}

/// @nodoc


class IdleAgentStateRead implements AgentStateRead {
  const IdleAgentStateRead({required this.budgetPause});


 final  AgentBudgetPauseRead? budgetPause;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IdleAgentStateReadCopyWith<IdleAgentStateRead> get copyWith => _$IdleAgentStateReadCopyWithImpl<IdleAgentStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IdleAgentStateRead&&(identical(other.budgetPause, budgetPause) || other.budgetPause == budgetPause));
}


@override
int get hashCode {
    return Object.hash(runtimeType,budgetPause);
}



}

/// @nodoc
abstract mixin class $IdleAgentStateReadCopyWith<$Res> implements $AgentStateReadCopyWith<$Res> {
  factory $IdleAgentStateReadCopyWith(IdleAgentStateRead value, $Res Function(IdleAgentStateRead) _then) = _$IdleAgentStateReadCopyWithImpl;
@useResult
$Res call({
 AgentBudgetPauseRead? budgetPause
});


$AgentBudgetPauseReadCopyWith<$Res>? get budgetPause;

}
/// @nodoc
class _$IdleAgentStateReadCopyWithImpl<$Res>
    implements $IdleAgentStateReadCopyWith<$Res> {
  _$IdleAgentStateReadCopyWithImpl(this._self, this._then);

  final IdleAgentStateRead _self;
  final $Res Function(IdleAgentStateRead) _then;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? budgetPause = freezed,}) {
  return _then(IdleAgentStateRead(
budgetPause: freezed == budgetPause ? _self.budgetPause : budgetPause // ignore: cast_nullable_to_non_nullable
as AgentBudgetPauseRead?,
  ));
}

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentBudgetPauseReadCopyWith<$Res>? get budgetPause {
    if (_self.budgetPause == null) {
    return null;
  }

  return $AgentBudgetPauseReadCopyWith<$Res>(_self.budgetPause!, (value) {
    return _then(_self.copyWith(budgetPause: value));
  });
}
}

/// @nodoc


class QueuedAgentStateRead implements AgentStateRead {
  const QueuedAgentStateRead({required this.turnId});


 final  ReadText turnId;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueuedAgentStateReadCopyWith<QueuedAgentStateRead> get copyWith => _$QueuedAgentStateReadCopyWithImpl<QueuedAgentStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueuedAgentStateRead&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}



}

/// @nodoc
abstract mixin class $QueuedAgentStateReadCopyWith<$Res> implements $AgentStateReadCopyWith<$Res> {
  factory $QueuedAgentStateReadCopyWith(QueuedAgentStateRead value, $Res Function(QueuedAgentStateRead) _then) = _$QueuedAgentStateReadCopyWithImpl;
@useResult
$Res call({
 ReadText turnId
});


$ReadTextCopyWith<$Res> get turnId;

}
/// @nodoc
class _$QueuedAgentStateReadCopyWithImpl<$Res>
    implements $QueuedAgentStateReadCopyWith<$Res> {
  _$QueuedAgentStateReadCopyWithImpl(this._self, this._then);

  final QueuedAgentStateRead _self;
  final $Res Function(QueuedAgentStateRead) _then;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(QueuedAgentStateRead(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

/// @nodoc


class RunningAgentStateRead implements AgentStateRead {
  const RunningAgentStateRead({required this.turnId});


 final  ReadText turnId;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RunningAgentStateReadCopyWith<RunningAgentStateRead> get copyWith => _$RunningAgentStateReadCopyWithImpl<RunningAgentStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RunningAgentStateRead&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}



}

/// @nodoc
abstract mixin class $RunningAgentStateReadCopyWith<$Res> implements $AgentStateReadCopyWith<$Res> {
  factory $RunningAgentStateReadCopyWith(RunningAgentStateRead value, $Res Function(RunningAgentStateRead) _then) = _$RunningAgentStateReadCopyWithImpl;
@useResult
$Res call({
 ReadText turnId
});


$ReadTextCopyWith<$Res> get turnId;

}
/// @nodoc
class _$RunningAgentStateReadCopyWithImpl<$Res>
    implements $RunningAgentStateReadCopyWith<$Res> {
  _$RunningAgentStateReadCopyWithImpl(this._self, this._then);

  final RunningAgentStateRead _self;
  final $Res Function(RunningAgentStateRead) _then;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(RunningAgentStateRead(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

/// @nodoc


class WaitingToolAgentStateRead implements AgentStateRead {
  const WaitingToolAgentStateRead({required this.turnId});


 final  ReadText turnId;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WaitingToolAgentStateReadCopyWith<WaitingToolAgentStateRead> get copyWith => _$WaitingToolAgentStateReadCopyWithImpl<WaitingToolAgentStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is WaitingToolAgentStateRead&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}



}

/// @nodoc
abstract mixin class $WaitingToolAgentStateReadCopyWith<$Res> implements $AgentStateReadCopyWith<$Res> {
  factory $WaitingToolAgentStateReadCopyWith(WaitingToolAgentStateRead value, $Res Function(WaitingToolAgentStateRead) _then) = _$WaitingToolAgentStateReadCopyWithImpl;
@useResult
$Res call({
 ReadText turnId
});


$ReadTextCopyWith<$Res> get turnId;

}
/// @nodoc
class _$WaitingToolAgentStateReadCopyWithImpl<$Res>
    implements $WaitingToolAgentStateReadCopyWith<$Res> {
  _$WaitingToolAgentStateReadCopyWithImpl(this._self, this._then);

  final WaitingToolAgentStateRead _self;
  final $Res Function(WaitingToolAgentStateRead) _then;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(WaitingToolAgentStateRead(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

/// @nodoc


class WaitingInteractionAgentStateRead implements AgentStateRead {
  const WaitingInteractionAgentStateRead({required this.turnId, required this.interactionId});


 final  ReadText turnId;
 final  ReadText interactionId;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WaitingInteractionAgentStateReadCopyWith<WaitingInteractionAgentStateRead> get copyWith => _$WaitingInteractionAgentStateReadCopyWithImpl<WaitingInteractionAgentStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is WaitingInteractionAgentStateRead&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.interactionId, interactionId) || other.interactionId == interactionId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId,interactionId);
}



}

/// @nodoc
abstract mixin class $WaitingInteractionAgentStateReadCopyWith<$Res> implements $AgentStateReadCopyWith<$Res> {
  factory $WaitingInteractionAgentStateReadCopyWith(WaitingInteractionAgentStateRead value, $Res Function(WaitingInteractionAgentStateRead) _then) = _$WaitingInteractionAgentStateReadCopyWithImpl;
@useResult
$Res call({
 ReadText turnId, ReadText interactionId
});


$ReadTextCopyWith<$Res> get turnId;$ReadTextCopyWith<$Res> get interactionId;

}
/// @nodoc
class _$WaitingInteractionAgentStateReadCopyWithImpl<$Res>
    implements $WaitingInteractionAgentStateReadCopyWith<$Res> {
  _$WaitingInteractionAgentStateReadCopyWithImpl(this._self, this._then);

  final WaitingInteractionAgentStateRead _self;
  final $Res Function(WaitingInteractionAgentStateRead) _then;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,Object? interactionId = null,}) {
  return _then(WaitingInteractionAgentStateRead(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get interactionId {

  return $ReadTextCopyWith<$Res>(_self.interactionId, (value) {
    return _then(_self.copyWith(interactionId: value));
  });
}
}

/// @nodoc


class CancellingAgentStateRead implements AgentStateRead {
  const CancellingAgentStateRead({required this.turnId});


 final  ReadText turnId;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancellingAgentStateReadCopyWith<CancellingAgentStateRead> get copyWith => _$CancellingAgentStateReadCopyWithImpl<CancellingAgentStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancellingAgentStateRead&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}



}

/// @nodoc
abstract mixin class $CancellingAgentStateReadCopyWith<$Res> implements $AgentStateReadCopyWith<$Res> {
  factory $CancellingAgentStateReadCopyWith(CancellingAgentStateRead value, $Res Function(CancellingAgentStateRead) _then) = _$CancellingAgentStateReadCopyWithImpl;
@useResult
$Res call({
 ReadText turnId
});


$ReadTextCopyWith<$Res> get turnId;

}
/// @nodoc
class _$CancellingAgentStateReadCopyWithImpl<$Res>
    implements $CancellingAgentStateReadCopyWith<$Res> {
  _$CancellingAgentStateReadCopyWithImpl(this._self, this._then);

  final CancellingAgentStateRead _self;
  final $Res Function(CancellingAgentStateRead) _then;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(CancellingAgentStateRead(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

/// @nodoc


class ClosingAgentStateRead implements AgentStateRead {
  const ClosingAgentStateRead({required this.workspaceDisposition, required this.turnId, required this.error});


 final  AgentWorkspaceDisposition workspaceDisposition;
 final  ReadText? turnId;
 final  SourceStateErrorRead? error;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClosingAgentStateReadCopyWith<ClosingAgentStateRead> get copyWith => _$ClosingAgentStateReadCopyWithImpl<ClosingAgentStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ClosingAgentStateRead&&(identical(other.workspaceDisposition, workspaceDisposition) || other.workspaceDisposition == workspaceDisposition)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,workspaceDisposition,turnId,error);
}



}

/// @nodoc
abstract mixin class $ClosingAgentStateReadCopyWith<$Res> implements $AgentStateReadCopyWith<$Res> {
  factory $ClosingAgentStateReadCopyWith(ClosingAgentStateRead value, $Res Function(ClosingAgentStateRead) _then) = _$ClosingAgentStateReadCopyWithImpl;
@useResult
$Res call({
 AgentWorkspaceDisposition workspaceDisposition, ReadText? turnId, SourceStateErrorRead? error
});


$ReadTextCopyWith<$Res>? get turnId;$SourceStateErrorReadCopyWith<$Res>? get error;

}
/// @nodoc
class _$ClosingAgentStateReadCopyWithImpl<$Res>
    implements $ClosingAgentStateReadCopyWith<$Res> {
  _$ClosingAgentStateReadCopyWithImpl(this._self, this._then);

  final ClosingAgentStateRead _self;
  final $Res Function(ClosingAgentStateRead) _then;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? workspaceDisposition = null,Object? turnId = freezed,Object? error = freezed,}) {
  return _then(ClosingAgentStateRead(
workspaceDisposition: null == workspaceDisposition ? _self.workspaceDisposition : workspaceDisposition // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceDisposition,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead?,
  ));
}

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get turnId {
    if (_self.turnId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.turnId!, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorReadCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $SourceStateErrorReadCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class ClosedAgentStateRead implements AgentStateRead {
  const ClosedAgentStateRead();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ClosedAgentStateRead);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class FaultedAgentStateRead implements AgentStateRead {
  const FaultedAgentStateRead({required this.error, required this.turnId, required this.classification});


 final  SourceStateErrorRead error;
 final  ReadText? turnId;
 final  AgentFaultClassification classification;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FaultedAgentStateReadCopyWith<FaultedAgentStateRead> get copyWith => _$FaultedAgentStateReadCopyWithImpl<FaultedAgentStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FaultedAgentStateRead&&(identical(other.error, error) || other.error == error)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.classification, classification) || other.classification == classification));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error,turnId,classification);
}



}

/// @nodoc
abstract mixin class $FaultedAgentStateReadCopyWith<$Res> implements $AgentStateReadCopyWith<$Res> {
  factory $FaultedAgentStateReadCopyWith(FaultedAgentStateRead value, $Res Function(FaultedAgentStateRead) _then) = _$FaultedAgentStateReadCopyWithImpl;
@useResult
$Res call({
 SourceStateErrorRead error, ReadText? turnId, AgentFaultClassification classification
});


$SourceStateErrorReadCopyWith<$Res> get error;$ReadTextCopyWith<$Res>? get turnId;

}
/// @nodoc
class _$FaultedAgentStateReadCopyWithImpl<$Res>
    implements $FaultedAgentStateReadCopyWith<$Res> {
  _$FaultedAgentStateReadCopyWithImpl(this._self, this._then);

  final FaultedAgentStateRead _self;
  final $Res Function(FaultedAgentStateRead) _then;

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,Object? turnId = freezed,Object? classification = null,}) {
  return _then(FaultedAgentStateRead(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText?,classification: null == classification ? _self.classification : classification // ignore: cast_nullable_to_non_nullable
as AgentFaultClassification,
  ));
}

/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorReadCopyWith<$Res> get error {

  return $SourceStateErrorReadCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of AgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get turnId {
    if (_self.turnId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.turnId!, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

/// @nodoc
mixin _$AgentDirectoryEntryRead {

 ReadText get id; ReadText get threadId; ReadText get rootThreadId; ReadText get path; ReadText? get parentPath; ReadText get role; ReadText get task; ReadText? get summary; DelegationMode get delegationMode; DelegationPreference get delegationPreference; FrozenModelSelectionRead? get frozenModel; int get depth; AgentStateRead get state; AgentExecution? get execution; bool get canStop; bool get awaitingScheduling; int get updatedAt;
/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryEntryReadCopyWith<AgentDirectoryEntryRead> get copyWith => _$AgentDirectoryEntryReadCopyWithImpl<AgentDirectoryEntryRead>(this as AgentDirectoryEntryRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryEntryRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryEntryRead&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.rootThreadId, _this.rootThreadId) || other.rootThreadId == _this.rootThreadId)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.parentPath, _this.parentPath) || other.parentPath == _this.parentPath)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.task, _this.task) || other.task == _this.task)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.delegationMode, _this.delegationMode) || other.delegationMode == _this.delegationMode)&&(identical(other.delegationPreference, _this.delegationPreference) || other.delegationPreference == _this.delegationPreference)&&(identical(other.frozenModel, _this.frozenModel) || other.frozenModel == _this.frozenModel)&&(identical(other.depth, _this.depth) || other.depth == _this.depth)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.execution, _this.execution) || other.execution == _this.execution)&&(identical(other.canStop, _this.canStop) || other.canStop == _this.canStop)&&(identical(other.awaitingScheduling, _this.awaitingScheduling) || other.awaitingScheduling == _this.awaitingScheduling)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryEntryRead;
  return Object.hash(runtimeType,_this.id,_this.threadId,_this.rootThreadId,_this.path,_this.parentPath,_this.role,_this.task,_this.summary,_this.delegationMode,_this.delegationPreference,_this.frozenModel,_this.depth,_this.state,_this.execution,_this.canStop,_this.awaitingScheduling,_this.updatedAt);
}



}

/// @nodoc
abstract mixin class $AgentDirectoryEntryReadCopyWith<$Res>  {
  factory $AgentDirectoryEntryReadCopyWith(AgentDirectoryEntryRead value, $Res Function(AgentDirectoryEntryRead) _then) = _$AgentDirectoryEntryReadCopyWithImpl;
@useResult
$Res call({
 ReadText id, ReadText threadId, ReadText rootThreadId, ReadText path, ReadText? parentPath, ReadText role, ReadText task, ReadText? summary, DelegationMode delegationMode, DelegationPreference delegationPreference, FrozenModelSelectionRead? frozenModel, int depth, AgentStateRead state, AgentExecution? execution, bool canStop, bool awaitingScheduling, int updatedAt
});


$ReadTextCopyWith<$Res> get id;$ReadTextCopyWith<$Res> get threadId;$ReadTextCopyWith<$Res> get rootThreadId;$ReadTextCopyWith<$Res> get path;$ReadTextCopyWith<$Res>? get parentPath;$ReadTextCopyWith<$Res> get role;$ReadTextCopyWith<$Res> get task;$ReadTextCopyWith<$Res>? get summary;$FrozenModelSelectionReadCopyWith<$Res>? get frozenModel;$AgentStateReadCopyWith<$Res> get state;$AgentExecutionCopyWith<$Res>? get execution;

}
/// @nodoc
class _$AgentDirectoryEntryReadCopyWithImpl<$Res>
    implements $AgentDirectoryEntryReadCopyWith<$Res> {
  _$AgentDirectoryEntryReadCopyWithImpl(this._self, this._then);

  final AgentDirectoryEntryRead _self;
  final $Res Function(AgentDirectoryEntryRead) _then;

/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? threadId = null,Object? rootThreadId = null,Object? path = null,Object? parentPath = freezed,Object? role = null,Object? task = null,Object? summary = freezed,Object? delegationMode = null,Object? delegationPreference = null,Object? frozenModel = freezed,Object? depth = null,Object? state = null,Object? execution = freezed,Object? canStop = null,Object? awaitingScheduling = null,Object? updatedAt = null,}) {
  return _then(AgentDirectoryEntryRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as ReadText,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,parentPath: freezed == parentPath ? _self.parentPath : parentPath // ignore: cast_nullable_to_non_nullable
as ReadText?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ReadText,task: null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as ReadText,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as ReadText?,delegationMode: null == delegationMode ? _self.delegationMode : delegationMode // ignore: cast_nullable_to_non_nullable
as DelegationMode,delegationPreference: null == delegationPreference ? _self.delegationPreference : delegationPreference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,frozenModel: freezed == frozenModel ? _self.frozenModel : frozenModel // ignore: cast_nullable_to_non_nullable
as FrozenModelSelectionRead?,depth: null == depth ? _self.depth : depth // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AgentStateRead,execution: freezed == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as AgentExecution?,canStop: null == canStop ? _self.canStop : canStop // ignore: cast_nullable_to_non_nullable
as bool,awaitingScheduling: null == awaitingScheduling ? _self.awaitingScheduling : awaitingScheduling // ignore: cast_nullable_to_non_nullable
as bool,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get rootThreadId {

  return $ReadTextCopyWith<$Res>(_self.rootThreadId, (value) {
    return _then(_self.copyWith(rootThreadId: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get parentPath {
    if (_self.parentPath == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.parentPath!, (value) {
    return _then(_self.copyWith(parentPath: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get role {

  return $ReadTextCopyWith<$Res>(_self.role, (value) {
    return _then(_self.copyWith(role: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get task {

  return $ReadTextCopyWith<$Res>(_self.task, (value) {
    return _then(_self.copyWith(task: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get summary {
    if (_self.summary == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.summary!, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FrozenModelSelectionReadCopyWith<$Res>? get frozenModel {
    if (_self.frozenModel == null) {
    return null;
  }

  return $FrozenModelSelectionReadCopyWith<$Res>(_self.frozenModel!, (value) {
    return _then(_self.copyWith(frozenModel: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentStateReadCopyWith<$Res> get state {

  return $AgentStateReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentExecutionCopyWith<$Res>? get execution {
    if (_self.execution == null) {
    return null;
  }

  return $AgentExecutionCopyWith<$Res>(_self.execution!, (value) {
    return _then(_self.copyWith(execution: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentDirectoryEntryRead].
extension AgentDirectoryEntryReadPatterns on AgentDirectoryEntryRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentDirectoryEntryRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentDirectoryEntryRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentDirectoryEntryRead value)  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryEntryRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentDirectoryEntryRead value)?  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryEntryRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText id,  ReadText threadId,  ReadText rootThreadId,  ReadText path,  ReadText? parentPath,  ReadText role,  ReadText task,  ReadText? summary,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  FrozenModelSelectionRead? frozenModel,  int depth,  AgentStateRead state,  AgentExecution? execution,  bool canStop,  bool awaitingScheduling,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentDirectoryEntryRead() when $default != null:
return $default(_that.id,_that.threadId,_that.rootThreadId,_that.path,_that.parentPath,_that.role,_that.task,_that.summary,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.depth,_that.state,_that.execution,_that.canStop,_that.awaitingScheduling,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText id,  ReadText threadId,  ReadText rootThreadId,  ReadText path,  ReadText? parentPath,  ReadText role,  ReadText task,  ReadText? summary,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  FrozenModelSelectionRead? frozenModel,  int depth,  AgentStateRead state,  AgentExecution? execution,  bool canStop,  bool awaitingScheduling,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryEntryRead():
return $default(_that.id,_that.threadId,_that.rootThreadId,_that.path,_that.parentPath,_that.role,_that.task,_that.summary,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.depth,_that.state,_that.execution,_that.canStop,_that.awaitingScheduling,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText id,  ReadText threadId,  ReadText rootThreadId,  ReadText path,  ReadText? parentPath,  ReadText role,  ReadText task,  ReadText? summary,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  FrozenModelSelectionRead? frozenModel,  int depth,  AgentStateRead state,  AgentExecution? execution,  bool canStop,  bool awaitingScheduling,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryEntryRead() when $default != null:
return $default(_that.id,_that.threadId,_that.rootThreadId,_that.path,_that.parentPath,_that.role,_that.task,_that.summary,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.depth,_that.state,_that.execution,_that.canStop,_that.awaitingScheduling,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _AgentDirectoryEntryRead implements AgentDirectoryEntryRead {
  const _AgentDirectoryEntryRead({required this.id, required this.threadId, required this.rootThreadId, required this.path, required this.parentPath, required this.role, required this.task, required this.summary, required this.delegationMode, required this.delegationPreference, required this.frozenModel, required this.depth, required this.state, required this.execution, required this.canStop, required this.awaitingScheduling, required this.updatedAt});


@override final  ReadText id;
@override final  ReadText threadId;
@override final  ReadText rootThreadId;
@override final  ReadText path;
@override final  ReadText? parentPath;
@override final  ReadText role;
@override final  ReadText task;
@override final  ReadText? summary;
@override final  DelegationMode delegationMode;
@override final  DelegationPreference delegationPreference;
@override final  FrozenModelSelectionRead? frozenModel;
@override final  int depth;
@override final  AgentStateRead state;
@override final  AgentExecution? execution;
@override final  bool canStop;
@override final  bool awaitingScheduling;
@override final  int updatedAt;

/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentDirectoryEntryReadCopyWith<_AgentDirectoryEntryRead> get copyWith => __$AgentDirectoryEntryReadCopyWithImpl<_AgentDirectoryEntryRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentDirectoryEntryRead&&(identical(other.id, id) || other.id == id)&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.rootThreadId, rootThreadId) || other.rootThreadId == rootThreadId)&&(identical(other.path, path) || other.path == path)&&(identical(other.parentPath, parentPath) || other.parentPath == parentPath)&&(identical(other.role, role) || other.role == role)&&(identical(other.task, task) || other.task == task)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.delegationMode, delegationMode) || other.delegationMode == delegationMode)&&(identical(other.delegationPreference, delegationPreference) || other.delegationPreference == delegationPreference)&&(identical(other.frozenModel, frozenModel) || other.frozenModel == frozenModel)&&(identical(other.depth, depth) || other.depth == depth)&&(identical(other.state, state) || other.state == state)&&(identical(other.execution, execution) || other.execution == execution)&&(identical(other.canStop, canStop) || other.canStop == canStop)&&(identical(other.awaitingScheduling, awaitingScheduling) || other.awaitingScheduling == awaitingScheduling)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,threadId,rootThreadId,path,parentPath,role,task,summary,delegationMode,delegationPreference,frozenModel,depth,state,execution,canStop,awaitingScheduling,updatedAt);
}



}

/// @nodoc
abstract mixin class _$AgentDirectoryEntryReadCopyWith<$Res> implements $AgentDirectoryEntryReadCopyWith<$Res> {
  factory _$AgentDirectoryEntryReadCopyWith(_AgentDirectoryEntryRead value, $Res Function(_AgentDirectoryEntryRead) _then) = __$AgentDirectoryEntryReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText id, ReadText threadId, ReadText rootThreadId, ReadText path, ReadText? parentPath, ReadText role, ReadText task, ReadText? summary, DelegationMode delegationMode, DelegationPreference delegationPreference, FrozenModelSelectionRead? frozenModel, int depth, AgentStateRead state, AgentExecution? execution, bool canStop, bool awaitingScheduling, int updatedAt
});


@override $ReadTextCopyWith<$Res> get id;@override $ReadTextCopyWith<$Res> get threadId;@override $ReadTextCopyWith<$Res> get rootThreadId;@override $ReadTextCopyWith<$Res> get path;@override $ReadTextCopyWith<$Res>? get parentPath;@override $ReadTextCopyWith<$Res> get role;@override $ReadTextCopyWith<$Res> get task;@override $ReadTextCopyWith<$Res>? get summary;@override $FrozenModelSelectionReadCopyWith<$Res>? get frozenModel;@override $AgentStateReadCopyWith<$Res> get state;@override $AgentExecutionCopyWith<$Res>? get execution;

}
/// @nodoc
class __$AgentDirectoryEntryReadCopyWithImpl<$Res>
    implements _$AgentDirectoryEntryReadCopyWith<$Res> {
  __$AgentDirectoryEntryReadCopyWithImpl(this._self, this._then);

  final _AgentDirectoryEntryRead _self;
  final $Res Function(_AgentDirectoryEntryRead) _then;

/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? threadId = null,Object? rootThreadId = null,Object? path = null,Object? parentPath = freezed,Object? role = null,Object? task = null,Object? summary = freezed,Object? delegationMode = null,Object? delegationPreference = null,Object? frozenModel = freezed,Object? depth = null,Object? state = null,Object? execution = freezed,Object? canStop = null,Object? awaitingScheduling = null,Object? updatedAt = null,}) {
  return _then(_AgentDirectoryEntryRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as ReadText,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,parentPath: freezed == parentPath ? _self.parentPath : parentPath // ignore: cast_nullable_to_non_nullable
as ReadText?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ReadText,task: null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as ReadText,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as ReadText?,delegationMode: null == delegationMode ? _self.delegationMode : delegationMode // ignore: cast_nullable_to_non_nullable
as DelegationMode,delegationPreference: null == delegationPreference ? _self.delegationPreference : delegationPreference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,frozenModel: freezed == frozenModel ? _self.frozenModel : frozenModel // ignore: cast_nullable_to_non_nullable
as FrozenModelSelectionRead?,depth: null == depth ? _self.depth : depth // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AgentStateRead,execution: freezed == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as AgentExecution?,canStop: null == canStop ? _self.canStop : canStop // ignore: cast_nullable_to_non_nullable
as bool,awaitingScheduling: null == awaitingScheduling ? _self.awaitingScheduling : awaitingScheduling // ignore: cast_nullable_to_non_nullable
as bool,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get rootThreadId {

  return $ReadTextCopyWith<$Res>(_self.rootThreadId, (value) {
    return _then(_self.copyWith(rootThreadId: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get parentPath {
    if (_self.parentPath == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.parentPath!, (value) {
    return _then(_self.copyWith(parentPath: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get role {

  return $ReadTextCopyWith<$Res>(_self.role, (value) {
    return _then(_self.copyWith(role: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get task {

  return $ReadTextCopyWith<$Res>(_self.task, (value) {
    return _then(_self.copyWith(task: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get summary {
    if (_self.summary == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.summary!, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FrozenModelSelectionReadCopyWith<$Res>? get frozenModel {
    if (_self.frozenModel == null) {
    return null;
  }

  return $FrozenModelSelectionReadCopyWith<$Res>(_self.frozenModel!, (value) {
    return _then(_self.copyWith(frozenModel: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentStateReadCopyWith<$Res> get state {

  return $AgentStateReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}/// Create a copy of AgentDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentExecutionCopyWith<$Res>? get execution {
    if (_self.execution == null) {
    return null;
  }

  return $AgentExecutionCopyWith<$Res>(_self.execution!, (value) {
    return _then(_self.copyWith(execution: value));
  });
}
}

/// @nodoc
mixin _$FrozenModelSelectionRead {

 ReadText get accountId; ReadText get modelId; ReadText? get effort;
/// Create a copy of FrozenModelSelectionRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrozenModelSelectionReadCopyWith<FrozenModelSelectionRead> get copyWith => _$FrozenModelSelectionReadCopyWithImpl<FrozenModelSelectionRead>(this as FrozenModelSelectionRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FrozenModelSelectionRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrozenModelSelectionRead&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as FrozenModelSelectionRead;
  return Object.hash(runtimeType,_this.accountId,_this.modelId,_this.effort);
}



}

/// @nodoc
abstract mixin class $FrozenModelSelectionReadCopyWith<$Res>  {
  factory $FrozenModelSelectionReadCopyWith(FrozenModelSelectionRead value, $Res Function(FrozenModelSelectionRead) _then) = _$FrozenModelSelectionReadCopyWithImpl;
@useResult
$Res call({
 ReadText accountId, ReadText modelId, ReadText? effort
});


$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res> get modelId;$ReadTextCopyWith<$Res>? get effort;

}
/// @nodoc
class _$FrozenModelSelectionReadCopyWithImpl<$Res>
    implements $FrozenModelSelectionReadCopyWith<$Res> {
  _$FrozenModelSelectionReadCopyWithImpl(this._self, this._then);

  final FrozenModelSelectionRead _self;
  final $Res Function(FrozenModelSelectionRead) _then;

/// Create a copy of FrozenModelSelectionRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? modelId = null,Object? effort = freezed,}) {
  return _then(FrozenModelSelectionRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of FrozenModelSelectionRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of FrozenModelSelectionRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of FrozenModelSelectionRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}
}


/// Adds pattern-matching-related methods to [FrozenModelSelectionRead].
extension FrozenModelSelectionReadPatterns on FrozenModelSelectionRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrozenModelSelectionRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrozenModelSelectionRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrozenModelSelectionRead value)  $default,){
final _that = this;
switch (_that) {
case _FrozenModelSelectionRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrozenModelSelectionRead value)?  $default,){
final _that = this;
switch (_that) {
case _FrozenModelSelectionRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText accountId,  ReadText modelId,  ReadText? effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrozenModelSelectionRead() when $default != null:
return $default(_that.accountId,_that.modelId,_that.effort);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText accountId,  ReadText modelId,  ReadText? effort)  $default,) {final _that = this;
switch (_that) {
case _FrozenModelSelectionRead():
return $default(_that.accountId,_that.modelId,_that.effort);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText accountId,  ReadText modelId,  ReadText? effort)?  $default,) {final _that = this;
switch (_that) {
case _FrozenModelSelectionRead() when $default != null:
return $default(_that.accountId,_that.modelId,_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _FrozenModelSelectionRead implements FrozenModelSelectionRead {
  const _FrozenModelSelectionRead({required this.accountId, required this.modelId, required this.effort});


@override final  ReadText accountId;
@override final  ReadText modelId;
@override final  ReadText? effort;

/// Create a copy of FrozenModelSelectionRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrozenModelSelectionReadCopyWith<_FrozenModelSelectionRead> get copyWith => __$FrozenModelSelectionReadCopyWithImpl<_FrozenModelSelectionRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrozenModelSelectionRead&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,modelId,effort);
}



}

/// @nodoc
abstract mixin class _$FrozenModelSelectionReadCopyWith<$Res> implements $FrozenModelSelectionReadCopyWith<$Res> {
  factory _$FrozenModelSelectionReadCopyWith(_FrozenModelSelectionRead value, $Res Function(_FrozenModelSelectionRead) _then) = __$FrozenModelSelectionReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText accountId, ReadText modelId, ReadText? effort
});


@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res> get modelId;@override $ReadTextCopyWith<$Res>? get effort;

}
/// @nodoc
class __$FrozenModelSelectionReadCopyWithImpl<$Res>
    implements _$FrozenModelSelectionReadCopyWith<$Res> {
  __$FrozenModelSelectionReadCopyWithImpl(this._self, this._then);

  final _FrozenModelSelectionRead _self;
  final $Res Function(_FrozenModelSelectionRead) _then;

/// Create a copy of FrozenModelSelectionRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? modelId = null,Object? effort = freezed,}) {
  return _then(_FrozenModelSelectionRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of FrozenModelSelectionRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of FrozenModelSelectionRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of FrozenModelSelectionRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}
}

/// @nodoc
mixin _$ProjectDirectoryEntityRead {

 ProductEntityRef get reference; ProjectRecordRead get value;
/// Create a copy of ProjectDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryEntityReadCopyWith<ProjectDirectoryEntityRead> get copyWith => _$ProjectDirectoryEntityReadCopyWithImpl<ProjectDirectoryEntityRead>(this as ProjectDirectoryEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectDirectoryEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ProjectDirectoryEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}



}

/// @nodoc
abstract mixin class $ProjectDirectoryEntityReadCopyWith<$Res>  {
  factory $ProjectDirectoryEntityReadCopyWith(ProjectDirectoryEntityRead value, $Res Function(ProjectDirectoryEntityRead) _then) = _$ProjectDirectoryEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, ProjectRecordRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$ProjectRecordReadCopyWith<$Res> get value;

}
/// @nodoc
class _$ProjectDirectoryEntityReadCopyWithImpl<$Res>
    implements $ProjectDirectoryEntityReadCopyWith<$Res> {
  _$ProjectDirectoryEntityReadCopyWithImpl(this._self, this._then);

  final ProjectDirectoryEntityRead _self;
  final $Res Function(ProjectDirectoryEntityRead) _then;

/// Create a copy of ProjectDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(ProjectDirectoryEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ProjectRecordRead,
  ));
}
/// Create a copy of ProjectDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ProjectDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectRecordReadCopyWith<$Res> get value {

  return $ProjectRecordReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProjectDirectoryEntityRead].
extension ProjectDirectoryEntityReadPatterns on ProjectDirectoryEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectDirectoryEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectDirectoryEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectDirectoryEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectDirectoryEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  ProjectRecordRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectDirectoryEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  ProjectRecordRead value)  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryEntityRead():
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  ProjectRecordRead value)?  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ProjectDirectoryEntityRead implements ProjectDirectoryEntityRead {
  const _ProjectDirectoryEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  ProjectRecordRead value;

/// Create a copy of ProjectDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectDirectoryEntityReadCopyWith<_ProjectDirectoryEntityRead> get copyWith => __$ProjectDirectoryEntityReadCopyWithImpl<_ProjectDirectoryEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectDirectoryEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}



}

/// @nodoc
abstract mixin class _$ProjectDirectoryEntityReadCopyWith<$Res> implements $ProjectDirectoryEntityReadCopyWith<$Res> {
  factory _$ProjectDirectoryEntityReadCopyWith(_ProjectDirectoryEntityRead value, $Res Function(_ProjectDirectoryEntityRead) _then) = __$ProjectDirectoryEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, ProjectRecordRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $ProjectRecordReadCopyWith<$Res> get value;

}
/// @nodoc
class __$ProjectDirectoryEntityReadCopyWithImpl<$Res>
    implements _$ProjectDirectoryEntityReadCopyWith<$Res> {
  __$ProjectDirectoryEntityReadCopyWithImpl(this._self, this._then);

  final _ProjectDirectoryEntityRead _self;
  final $Res Function(_ProjectDirectoryEntityRead) _then;

/// Create a copy of ProjectDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_ProjectDirectoryEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ProjectRecordRead,
  ));
}

/// Create a copy of ProjectDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ProjectDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectRecordReadCopyWith<$Res> get value {

  return $ProjectRecordReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadDirectoryEntityRead {

 ProductEntityRef get reference; WorkspaceThreadRecordRead get value;
/// Create a copy of ThreadDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryEntityReadCopyWith<ThreadDirectoryEntityRead> get copyWith => _$ThreadDirectoryEntityReadCopyWithImpl<ThreadDirectoryEntityRead>(this as ThreadDirectoryEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadDirectoryEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadDirectoryEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}



}

/// @nodoc
abstract mixin class $ThreadDirectoryEntityReadCopyWith<$Res>  {
  factory $ThreadDirectoryEntityReadCopyWith(ThreadDirectoryEntityRead value, $Res Function(ThreadDirectoryEntityRead) _then) = _$ThreadDirectoryEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, WorkspaceThreadRecordRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$WorkspaceThreadRecordReadCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadDirectoryEntityReadCopyWithImpl<$Res>
    implements $ThreadDirectoryEntityReadCopyWith<$Res> {
  _$ThreadDirectoryEntityReadCopyWithImpl(this._self, this._then);

  final ThreadDirectoryEntityRead _self;
  final $Res Function(ThreadDirectoryEntityRead) _then;

/// Create a copy of ThreadDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(ThreadDirectoryEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as WorkspaceThreadRecordRead,
  ));
}
/// Create a copy of ThreadDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ThreadDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordReadCopyWith<$Res> get value {

  return $WorkspaceThreadRecordReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadDirectoryEntityRead].
extension ThreadDirectoryEntityReadPatterns on ThreadDirectoryEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadDirectoryEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadDirectoryEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadDirectoryEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadDirectoryEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  WorkspaceThreadRecordRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadDirectoryEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  WorkspaceThreadRecordRead value)  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryEntityRead():
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  WorkspaceThreadRecordRead value)?  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadDirectoryEntityRead implements ThreadDirectoryEntityRead {
  const _ThreadDirectoryEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  WorkspaceThreadRecordRead value;

/// Create a copy of ThreadDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadDirectoryEntityReadCopyWith<_ThreadDirectoryEntityRead> get copyWith => __$ThreadDirectoryEntityReadCopyWithImpl<_ThreadDirectoryEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadDirectoryEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}



}

/// @nodoc
abstract mixin class _$ThreadDirectoryEntityReadCopyWith<$Res> implements $ThreadDirectoryEntityReadCopyWith<$Res> {
  factory _$ThreadDirectoryEntityReadCopyWith(_ThreadDirectoryEntityRead value, $Res Function(_ThreadDirectoryEntityRead) _then) = __$ThreadDirectoryEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, WorkspaceThreadRecordRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $WorkspaceThreadRecordReadCopyWith<$Res> get value;

}
/// @nodoc
class __$ThreadDirectoryEntityReadCopyWithImpl<$Res>
    implements _$ThreadDirectoryEntityReadCopyWith<$Res> {
  __$ThreadDirectoryEntityReadCopyWithImpl(this._self, this._then);

  final _ThreadDirectoryEntityRead _self;
  final $Res Function(_ThreadDirectoryEntityRead) _then;

/// Create a copy of ThreadDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_ThreadDirectoryEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as WorkspaceThreadRecordRead,
  ));
}

/// Create a copy of ThreadDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ThreadDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordReadCopyWith<$Res> get value {

  return $WorkspaceThreadRecordReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$AgentDirectoryEntityRead {

 ProductEntityRef get reference; AgentDirectoryEntryRead get value;
/// Create a copy of AgentDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryEntityReadCopyWith<AgentDirectoryEntityRead> get copyWith => _$AgentDirectoryEntityReadCopyWithImpl<AgentDirectoryEntityRead>(this as AgentDirectoryEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}



}

/// @nodoc
abstract mixin class $AgentDirectoryEntityReadCopyWith<$Res>  {
  factory $AgentDirectoryEntityReadCopyWith(AgentDirectoryEntityRead value, $Res Function(AgentDirectoryEntityRead) _then) = _$AgentDirectoryEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, AgentDirectoryEntryRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$AgentDirectoryEntryReadCopyWith<$Res> get value;

}
/// @nodoc
class _$AgentDirectoryEntityReadCopyWithImpl<$Res>
    implements $AgentDirectoryEntityReadCopyWith<$Res> {
  _$AgentDirectoryEntityReadCopyWithImpl(this._self, this._then);

  final AgentDirectoryEntityRead _self;
  final $Res Function(AgentDirectoryEntityRead) _then;

/// Create a copy of AgentDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(AgentDirectoryEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AgentDirectoryEntryRead,
  ));
}
/// Create a copy of AgentDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of AgentDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryEntryReadCopyWith<$Res> get value {

  return $AgentDirectoryEntryReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentDirectoryEntityRead].
extension AgentDirectoryEntityReadPatterns on AgentDirectoryEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentDirectoryEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentDirectoryEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentDirectoryEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentDirectoryEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  AgentDirectoryEntryRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentDirectoryEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  AgentDirectoryEntryRead value)  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryEntityRead():
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  AgentDirectoryEntryRead value)?  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _AgentDirectoryEntityRead implements AgentDirectoryEntityRead {
  const _AgentDirectoryEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  AgentDirectoryEntryRead value;

/// Create a copy of AgentDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentDirectoryEntityReadCopyWith<_AgentDirectoryEntityRead> get copyWith => __$AgentDirectoryEntityReadCopyWithImpl<_AgentDirectoryEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentDirectoryEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}



}

/// @nodoc
abstract mixin class _$AgentDirectoryEntityReadCopyWith<$Res> implements $AgentDirectoryEntityReadCopyWith<$Res> {
  factory _$AgentDirectoryEntityReadCopyWith(_AgentDirectoryEntityRead value, $Res Function(_AgentDirectoryEntityRead) _then) = __$AgentDirectoryEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, AgentDirectoryEntryRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $AgentDirectoryEntryReadCopyWith<$Res> get value;

}
/// @nodoc
class __$AgentDirectoryEntityReadCopyWithImpl<$Res>
    implements _$AgentDirectoryEntityReadCopyWith<$Res> {
  __$AgentDirectoryEntityReadCopyWithImpl(this._self, this._then);

  final _AgentDirectoryEntityRead _self;
  final $Res Function(_AgentDirectoryEntityRead) _then;

/// Create a copy of AgentDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_AgentDirectoryEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AgentDirectoryEntryRead,
  ));
}

/// Create a copy of AgentDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of AgentDirectoryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryEntryReadCopyWith<$Res> get value {

  return $AgentDirectoryEntryReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ProjectDirectoryEntryPage {


/// Create a copy of ProjectDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryEntryPageCopyWith<ProjectDirectoryEntryPage> get copyWith => _$ProjectDirectoryEntryPageCopyWithImpl<ProjectDirectoryEntryPage>(this as ProjectDirectoryEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectDirectoryEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as ProjectDirectoryEntryPage;
  return Object.hash(runtimeType,_this.collection,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as ProjectDirectoryEntryPage;
  return 'ProjectDirectoryEntryPage(collection: ${_this.collection}, offset: ${_this.offset}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $ProjectDirectoryEntryPageCopyWith<$Res>  {
  factory $ProjectDirectoryEntryPageCopyWith(ProjectDirectoryEntryPage value, $Res Function(ProjectDirectoryEntryPage) _then) = _$ProjectDirectoryEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


$ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class _$ProjectDirectoryEntryPageCopyWithImpl<$Res>
    implements $ProjectDirectoryEntryPageCopyWith<$Res> {
  _$ProjectDirectoryEntryPageCopyWithImpl(this._self, this._then);

  final ProjectDirectoryEntryPage _self;
  final $Res Function(ProjectDirectoryEntryPage) _then;

/// Create a copy of ProjectDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(ProjectDirectoryEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of ProjectDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProjectDirectoryEntryPage].
extension ProjectDirectoryEntryPagePatterns on ProjectDirectoryEntryPage {
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
mixin _$ThreadDirectoryEntryPage {


/// Create a copy of ThreadDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryEntryPageCopyWith<ThreadDirectoryEntryPage> get copyWith => _$ThreadDirectoryEntryPageCopyWithImpl<ThreadDirectoryEntryPage>(this as ThreadDirectoryEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadDirectoryEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor)&&(identical(other.hasMore, _this.hasMore) || other.hasMore == _this.hasMore));
}


@override
int get hashCode {
  final _this = this as ThreadDirectoryEntryPage;
  return Object.hash(runtimeType,_this.collection,const DeepCollectionEquality().hash(_this.items),_this.nextCursor,_this.hasMore);
}

@override
String toString() {
  final _this = this as ThreadDirectoryEntryPage;
  return 'ThreadDirectoryEntryPage(collection: ${_this.collection}, items: ${_this.items}, nextCursor: ${_this.nextCursor}, hasMore: ${_this.hasMore})';
}


}

/// @nodoc
abstract mixin class $ThreadDirectoryEntryPageCopyWith<$Res>  {
  factory $ThreadDirectoryEntryPageCopyWith(ThreadDirectoryEntryPage value, $Res Function(ThreadDirectoryEntryPage) _then) = _$ThreadDirectoryEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, List<ProductEntityRef> items, ReadText? nextCursor, bool hasMore
});


$ProductCollectionRefCopyWith<$Res> get collection;$ReadTextCopyWith<$Res>? get nextCursor;

}
/// @nodoc
class _$ThreadDirectoryEntryPageCopyWithImpl<$Res>
    implements $ThreadDirectoryEntryPageCopyWith<$Res> {
  _$ThreadDirectoryEntryPageCopyWithImpl(this._self, this._then);

  final ThreadDirectoryEntryPage _self;
  final $Res Function(ThreadDirectoryEntryPage) _then;

/// Create a copy of ThreadDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? items = null,Object? nextCursor = freezed,Object? hasMore = null,}) {
  return _then(ThreadDirectoryEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as ReadText?,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ThreadDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}/// Create a copy of ThreadDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get nextCursor {
    if (_self.nextCursor == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.nextCursor!, (value) {
    return _then(_self.copyWith(nextCursor: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadDirectoryEntryPage].
extension ThreadDirectoryEntryPagePatterns on ThreadDirectoryEntryPage {
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
mixin _$AgentDirectoryEntryPage {


/// Create a copy of AgentDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryEntryPageCopyWith<AgentDirectoryEntryPage> get copyWith => _$AgentDirectoryEntryPageCopyWithImpl<AgentDirectoryEntryPage>(this as AgentDirectoryEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryEntryPage;
  return Object.hash(runtimeType,_this.collection,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as AgentDirectoryEntryPage;
  return 'AgentDirectoryEntryPage(collection: ${_this.collection}, offset: ${_this.offset}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $AgentDirectoryEntryPageCopyWith<$Res>  {
  factory $AgentDirectoryEntryPageCopyWith(AgentDirectoryEntryPage value, $Res Function(AgentDirectoryEntryPage) _then) = _$AgentDirectoryEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


$ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class _$AgentDirectoryEntryPageCopyWithImpl<$Res>
    implements $AgentDirectoryEntryPageCopyWith<$Res> {
  _$AgentDirectoryEntryPageCopyWithImpl(this._self, this._then);

  final AgentDirectoryEntryPage _self;
  final $Res Function(AgentDirectoryEntryPage) _then;

/// Create a copy of AgentDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(AgentDirectoryEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of AgentDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentDirectoryEntryPage].
extension AgentDirectoryEntryPagePatterns on AgentDirectoryEntryPage {
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
mixin _$ProjectRecordReadPage {


/// Create a copy of ProjectRecordReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectRecordReadPageCopyWith<ProjectRecordReadPage> get copyWith => _$ProjectRecordReadPageCopyWithImpl<ProjectRecordReadPage>(this as ProjectRecordReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectRecordReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectRecordReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as ProjectRecordReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $ProjectRecordReadPageCopyWith<$Res>  {
  factory $ProjectRecordReadPageCopyWith(ProjectRecordReadPage value, $Res Function(ProjectRecordReadPage) _then) = _$ProjectRecordReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<ProjectRecordRead> items, int? nextOffset
});




}
/// @nodoc
class _$ProjectRecordReadPageCopyWithImpl<$Res>
    implements $ProjectRecordReadPageCopyWith<$Res> {
  _$ProjectRecordReadPageCopyWithImpl(this._self, this._then);

  final ProjectRecordReadPage _self;
  final $Res Function(ProjectRecordReadPage) _then;

/// Create a copy of ProjectRecordReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(ProjectRecordReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProjectRecordRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ProjectRecordReadPage].
extension ProjectRecordReadPagePatterns on ProjectRecordReadPage {
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
mixin _$WorkspaceThreadRecordReadPage {


/// Create a copy of WorkspaceThreadRecordReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordReadPageCopyWith<WorkspaceThreadRecordReadPage> get copyWith => _$WorkspaceThreadRecordReadPageCopyWithImpl<WorkspaceThreadRecordReadPage>(this as WorkspaceThreadRecordReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceThreadRecordReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceThreadRecordReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as WorkspaceThreadRecordReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $WorkspaceThreadRecordReadPageCopyWith<$Res>  {
  factory $WorkspaceThreadRecordReadPageCopyWith(WorkspaceThreadRecordReadPage value, $Res Function(WorkspaceThreadRecordReadPage) _then) = _$WorkspaceThreadRecordReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<WorkspaceThreadRecordRead> items, int? nextOffset
});




}
/// @nodoc
class _$WorkspaceThreadRecordReadPageCopyWithImpl<$Res>
    implements $WorkspaceThreadRecordReadPageCopyWith<$Res> {
  _$WorkspaceThreadRecordReadPageCopyWithImpl(this._self, this._then);

  final WorkspaceThreadRecordReadPage _self;
  final $Res Function(WorkspaceThreadRecordReadPage) _then;

/// Create a copy of WorkspaceThreadRecordReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(WorkspaceThreadRecordReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<WorkspaceThreadRecordRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkspaceThreadRecordReadPage].
extension WorkspaceThreadRecordReadPagePatterns on WorkspaceThreadRecordReadPage {
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
mixin _$AgentDirectoryEntryReadPage {


/// Create a copy of AgentDirectoryEntryReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryEntryReadPageCopyWith<AgentDirectoryEntryReadPage> get copyWith => _$AgentDirectoryEntryReadPageCopyWithImpl<AgentDirectoryEntryReadPage>(this as AgentDirectoryEntryReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryEntryReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryEntryReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryEntryReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $AgentDirectoryEntryReadPageCopyWith<$Res>  {
  factory $AgentDirectoryEntryReadPageCopyWith(AgentDirectoryEntryReadPage value, $Res Function(AgentDirectoryEntryReadPage) _then) = _$AgentDirectoryEntryReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<AgentDirectoryEntryRead> items, int? nextOffset
});




}
/// @nodoc
class _$AgentDirectoryEntryReadPageCopyWithImpl<$Res>
    implements $AgentDirectoryEntryReadPageCopyWith<$Res> {
  _$AgentDirectoryEntryReadPageCopyWithImpl(this._self, this._then);

  final AgentDirectoryEntryReadPage _self;
  final $Res Function(AgentDirectoryEntryReadPage) _then;

/// Create a copy of AgentDirectoryEntryReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(AgentDirectoryEntryReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<AgentDirectoryEntryRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentDirectoryEntryReadPage].
extension AgentDirectoryEntryReadPagePatterns on AgentDirectoryEntryReadPage {
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
