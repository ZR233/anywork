// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'directory_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DirectoryQuery {

 String? get projectId; String? get search; bool get archived; DirectoryFilter get filter;
/// Create a copy of DirectoryQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DirectoryQueryCopyWith<DirectoryQuery> get copyWith => _$DirectoryQueryCopyWithImpl<DirectoryQuery>(this as DirectoryQuery, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DirectoryQuery;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DirectoryQuery&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.search, _this.search) || other.search == _this.search)&&(identical(other.archived, _this.archived) || other.archived == _this.archived)&&(identical(other.filter, _this.filter) || other.filter == _this.filter));
}


@override
int get hashCode {
  final _this = this as DirectoryQuery;
  return Object.hash(runtimeType,_this.projectId,_this.search,_this.archived,_this.filter);
}

@override
String toString() {
  final _this = this as DirectoryQuery;
  return 'DirectoryQuery(projectId: ${_this.projectId}, search: ${_this.search}, archived: ${_this.archived}, filter: ${_this.filter})';
}


}

/// @nodoc
abstract mixin class $DirectoryQueryCopyWith<$Res>  {
  factory $DirectoryQueryCopyWith(DirectoryQuery value, $Res Function(DirectoryQuery) _then) = _$DirectoryQueryCopyWithImpl;
@useResult
$Res call({
 String? projectId, String? search, bool archived, DirectoryFilter filter
});




}
/// @nodoc
class _$DirectoryQueryCopyWithImpl<$Res>
    implements $DirectoryQueryCopyWith<$Res> {
  _$DirectoryQueryCopyWithImpl(this._self, this._then);

  final DirectoryQuery _self;
  final $Res Function(DirectoryQuery) _then;

/// Create a copy of DirectoryQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = freezed,Object? search = freezed,Object? archived = null,Object? filter = null,}) {
  return _then(DirectoryQuery(
projectId: freezed == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String?,search: freezed == search ? _self.search : search // ignore: cast_nullable_to_non_nullable
as String?,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as bool,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as DirectoryFilter,
  ));
}

}


/// Adds pattern-matching-related methods to [DirectoryQuery].
extension DirectoryQueryPatterns on DirectoryQuery {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DirectoryQuery value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DirectoryQuery() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DirectoryQuery value)  $default,){
final _that = this;
switch (_that) {
case _DirectoryQuery():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DirectoryQuery value)?  $default,){
final _that = this;
switch (_that) {
case _DirectoryQuery() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? projectId,  String? search,  bool archived,  DirectoryFilter filter)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DirectoryQuery() when $default != null:
return $default(_that.projectId,_that.search,_that.archived,_that.filter);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? projectId,  String? search,  bool archived,  DirectoryFilter filter)  $default,) {final _that = this;
switch (_that) {
case _DirectoryQuery():
return $default(_that.projectId,_that.search,_that.archived,_that.filter);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? projectId,  String? search,  bool archived,  DirectoryFilter filter)?  $default,) {final _that = this;
switch (_that) {
case _DirectoryQuery() when $default != null:
return $default(_that.projectId,_that.search,_that.archived,_that.filter);case _:
  return null;

}
}

}

/// @nodoc


class _DirectoryQuery implements DirectoryQuery {
  const _DirectoryQuery({required this.projectId, required this.search, required this.archived, required this.filter});


@override final  String? projectId;
@override final  String? search;
@override final  bool archived;
@override final  DirectoryFilter filter;

/// Create a copy of DirectoryQuery
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DirectoryQueryCopyWith<_DirectoryQuery> get copyWith => __$DirectoryQueryCopyWithImpl<_DirectoryQuery>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DirectoryQuery&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.search, search) || other.search == search)&&(identical(other.archived, archived) || other.archived == archived)&&(identical(other.filter, filter) || other.filter == filter));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projectId,search,archived,filter);
}

@override
String toString() {
    return 'DirectoryQuery(projectId: $projectId, search: $search, archived: $archived, filter: $filter)';
}


}

/// @nodoc
abstract mixin class _$DirectoryQueryCopyWith<$Res> implements $DirectoryQueryCopyWith<$Res> {
  factory _$DirectoryQueryCopyWith(_DirectoryQuery value, $Res Function(_DirectoryQuery) _then) = __$DirectoryQueryCopyWithImpl;
@override @useResult
$Res call({
 String? projectId, String? search, bool archived, DirectoryFilter filter
});




}
/// @nodoc
class __$DirectoryQueryCopyWithImpl<$Res>
    implements _$DirectoryQueryCopyWith<$Res> {
  __$DirectoryQueryCopyWithImpl(this._self, this._then);

  final _DirectoryQuery _self;
  final $Res Function(_DirectoryQuery) _then;

/// Create a copy of DirectoryQuery
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = freezed,Object? search = freezed,Object? archived = null,Object? filter = null,}) {
  return _then(_DirectoryQuery(
projectId: freezed == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String?,search: freezed == search ? _self.search : search // ignore: cast_nullable_to_non_nullable
as String?,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as bool,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as DirectoryFilter,
  ));
}


}

/// @nodoc
mixin _$ThreadDirectoryScope {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryScope);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ThreadDirectoryScope()';
}


}

/// @nodoc
class $ThreadDirectoryScopeCopyWith<$Res>  {
$ThreadDirectoryScopeCopyWith(ThreadDirectoryScope _, $Res Function(ThreadDirectoryScope) __);
}


/// Adds pattern-matching-related methods to [ThreadDirectoryScope].
extension ThreadDirectoryScopePatterns on ThreadDirectoryScope {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( QueryThreadDirectoryScope value)?  query,TResult Function( SingleThreadDirectoryScope value)?  thread,required TResult orElse(),}){
final _that = this;
switch (_that) {
case QueryThreadDirectoryScope() when query != null:
return query(_that);case SingleThreadDirectoryScope() when thread != null:
return thread(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( QueryThreadDirectoryScope value)  query,required TResult Function( SingleThreadDirectoryScope value)  thread,}){
final _that = this;
switch (_that) {
case QueryThreadDirectoryScope():
return query(_that);case SingleThreadDirectoryScope():
return thread(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( QueryThreadDirectoryScope value)?  query,TResult? Function( SingleThreadDirectoryScope value)?  thread,}){
final _that = this;
switch (_that) {
case QueryThreadDirectoryScope() when query != null:
return query(_that);case SingleThreadDirectoryScope() when thread != null:
return thread(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( DirectoryQuery query,  bool includePinned)?  query,TResult Function( String threadId)?  thread,required TResult orElse(),}) {final _that = this;
switch (_that) {
case QueryThreadDirectoryScope() when query != null:
return query(_that.query,_that.includePinned);case SingleThreadDirectoryScope() when thread != null:
return thread(_that.threadId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( DirectoryQuery query,  bool includePinned)  query,required TResult Function( String threadId)  thread,}) {final _that = this;
switch (_that) {
case QueryThreadDirectoryScope():
return query(_that.query,_that.includePinned);case SingleThreadDirectoryScope():
return thread(_that.threadId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( DirectoryQuery query,  bool includePinned)?  query,TResult? Function( String threadId)?  thread,}) {final _that = this;
switch (_that) {
case QueryThreadDirectoryScope() when query != null:
return query(_that.query,_that.includePinned);case SingleThreadDirectoryScope() when thread != null:
return thread(_that.threadId);case _:
  return null;

}
}

}

/// @nodoc


class QueryThreadDirectoryScope implements ThreadDirectoryScope {
  const QueryThreadDirectoryScope({required this.query, this.includePinned = true});


 final  DirectoryQuery query;
@JsonKey() final  bool includePinned;

/// Create a copy of ThreadDirectoryScope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueryThreadDirectoryScopeCopyWith<QueryThreadDirectoryScope> get copyWith => _$QueryThreadDirectoryScopeCopyWithImpl<QueryThreadDirectoryScope>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueryThreadDirectoryScope&&(identical(other.query, query) || other.query == query)&&(identical(other.includePinned, includePinned) || other.includePinned == includePinned));
}


@override
int get hashCode {
    return Object.hash(runtimeType,query,includePinned);
}

@override
String toString() {
    return 'ThreadDirectoryScope.query(query: $query, includePinned: $includePinned)';
}


}

/// @nodoc
abstract mixin class $QueryThreadDirectoryScopeCopyWith<$Res> implements $ThreadDirectoryScopeCopyWith<$Res> {
  factory $QueryThreadDirectoryScopeCopyWith(QueryThreadDirectoryScope value, $Res Function(QueryThreadDirectoryScope) _then) = _$QueryThreadDirectoryScopeCopyWithImpl;
@useResult
$Res call({
 DirectoryQuery query, bool includePinned
});


$DirectoryQueryCopyWith<$Res> get query;

}
/// @nodoc
class _$QueryThreadDirectoryScopeCopyWithImpl<$Res>
    implements $QueryThreadDirectoryScopeCopyWith<$Res> {
  _$QueryThreadDirectoryScopeCopyWithImpl(this._self, this._then);

  final QueryThreadDirectoryScope _self;
  final $Res Function(QueryThreadDirectoryScope) _then;

/// Create a copy of ThreadDirectoryScope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? query = null,Object? includePinned = null,}) {
  return _then(QueryThreadDirectoryScope(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as DirectoryQuery,includePinned: null == includePinned ? _self.includePinned : includePinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ThreadDirectoryScope
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DirectoryQueryCopyWith<$Res> get query {

  return $DirectoryQueryCopyWith<$Res>(_self.query, (value) {
    return _then(_self.copyWith(query: value));
  });
}
}

/// @nodoc


class SingleThreadDirectoryScope implements ThreadDirectoryScope {
  const SingleThreadDirectoryScope({required this.threadId});


 final  String threadId;

/// Create a copy of ThreadDirectoryScope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SingleThreadDirectoryScopeCopyWith<SingleThreadDirectoryScope> get copyWith => _$SingleThreadDirectoryScopeCopyWithImpl<SingleThreadDirectoryScope>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SingleThreadDirectoryScope&&(identical(other.threadId, threadId) || other.threadId == threadId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId);
}

@override
String toString() {
    return 'ThreadDirectoryScope.thread(threadId: $threadId)';
}


}

/// @nodoc
abstract mixin class $SingleThreadDirectoryScopeCopyWith<$Res> implements $ThreadDirectoryScopeCopyWith<$Res> {
  factory $SingleThreadDirectoryScopeCopyWith(SingleThreadDirectoryScope value, $Res Function(SingleThreadDirectoryScope) _then) = _$SingleThreadDirectoryScopeCopyWithImpl;
@useResult
$Res call({
 String threadId
});




}
/// @nodoc
class _$SingleThreadDirectoryScopeCopyWithImpl<$Res>
    implements $SingleThreadDirectoryScopeCopyWith<$Res> {
  _$SingleThreadDirectoryScopeCopyWithImpl(this._self, this._then);

  final SingleThreadDirectoryScope _self;
  final $Res Function(SingleThreadDirectoryScope) _then;

/// Create a copy of ThreadDirectoryScope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? threadId = null,}) {
  return _then(SingleThreadDirectoryScope(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ProjectRecord {

 String get id; String get name; String get path; String? get sshAlias; int get updatedAt;
/// Create a copy of ProjectRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectRecordCopyWith<ProjectRecord> get copyWith => _$ProjectRecordCopyWithImpl<ProjectRecord>(this as ProjectRecord, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectRecord;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectRecord&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.sshAlias, _this.sshAlias) || other.sshAlias == _this.sshAlias)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as ProjectRecord;
  return Object.hash(runtimeType,_this.id,_this.name,_this.path,_this.sshAlias,_this.updatedAt);
}



}

/// @nodoc
abstract mixin class $ProjectRecordCopyWith<$Res>  {
  factory $ProjectRecordCopyWith(ProjectRecord value, $Res Function(ProjectRecord) _then) = _$ProjectRecordCopyWithImpl;
@useResult
$Res call({
 String id, String name, String path, String? sshAlias, int updatedAt
});




}
/// @nodoc
class _$ProjectRecordCopyWithImpl<$Res>
    implements $ProjectRecordCopyWith<$Res> {
  _$ProjectRecordCopyWithImpl(this._self, this._then);

  final ProjectRecord _self;
  final $Res Function(ProjectRecord) _then;

/// Create a copy of ProjectRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? path = null,Object? sshAlias = freezed,Object? updatedAt = null,}) {
  return _then(ProjectRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,sshAlias: freezed == sshAlias ? _self.sshAlias : sshAlias // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProjectRecord].
extension ProjectRecordPatterns on ProjectRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectRecord value)  $default,){
final _that = this;
switch (_that) {
case _ProjectRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectRecord value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String path,  String? sshAlias,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectRecord() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String path,  String? sshAlias,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _ProjectRecord():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String path,  String? sshAlias,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _ProjectRecord() when $default != null:
return $default(_that.id,_that.name,_that.path,_that.sshAlias,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _ProjectRecord implements ProjectRecord {
  const _ProjectRecord({required this.id, required this.name, required this.path, required this.sshAlias, required this.updatedAt});


@override final  String id;
@override final  String name;
@override final  String path;
@override final  String? sshAlias;
@override final  int updatedAt;

/// Create a copy of ProjectRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectRecordCopyWith<_ProjectRecord> get copyWith => __$ProjectRecordCopyWithImpl<_ProjectRecord>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.path, path) || other.path == path)&&(identical(other.sshAlias, sshAlias) || other.sshAlias == sshAlias)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,path,sshAlias,updatedAt);
}



}

/// @nodoc
abstract mixin class _$ProjectRecordCopyWith<$Res> implements $ProjectRecordCopyWith<$Res> {
  factory _$ProjectRecordCopyWith(_ProjectRecord value, $Res Function(_ProjectRecord) _then) = __$ProjectRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String path, String? sshAlias, int updatedAt
});




}
/// @nodoc
class __$ProjectRecordCopyWithImpl<$Res>
    implements _$ProjectRecordCopyWith<$Res> {
  __$ProjectRecordCopyWithImpl(this._self, this._then);

  final _ProjectRecord _self;
  final $Res Function(_ProjectRecord) _then;

/// Create a copy of ProjectRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? path = null,Object? sshAlias = freezed,Object? updatedAt = null,}) {
  return _then(_ProjectRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,sshAlias: freezed == sshAlias ? _self.sshAlias : sshAlias // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$WorkspaceThreadRecord {

 String get id; String get projectId; String get title; ThreadModeId get mode; DelegationMode get delegationMode; DelegationPreference get delegationPreference; ModelSelection? get frozenModel; ThreadWorkspaceMode get workspaceMode; String get workspacePath; String get rootThreadId; String? get parentThreadId; String get role; String get agentPath; ThreadStatus get status; int get createdAt; int get updatedAt; int? get lastUserMessageAt; bool get archived;
/// Create a copy of WorkspaceThreadRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordCopyWith<WorkspaceThreadRecord> get copyWith => _$WorkspaceThreadRecordCopyWithImpl<WorkspaceThreadRecord>(this as WorkspaceThreadRecord, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceThreadRecord;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceThreadRecord&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.delegationMode, _this.delegationMode) || other.delegationMode == _this.delegationMode)&&(identical(other.delegationPreference, _this.delegationPreference) || other.delegationPreference == _this.delegationPreference)&&(identical(other.frozenModel, _this.frozenModel) || other.frozenModel == _this.frozenModel)&&(identical(other.workspaceMode, _this.workspaceMode) || other.workspaceMode == _this.workspaceMode)&&(identical(other.workspacePath, _this.workspacePath) || other.workspacePath == _this.workspacePath)&&(identical(other.rootThreadId, _this.rootThreadId) || other.rootThreadId == _this.rootThreadId)&&(identical(other.parentThreadId, _this.parentThreadId) || other.parentThreadId == _this.parentThreadId)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.agentPath, _this.agentPath) || other.agentPath == _this.agentPath)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.lastUserMessageAt, _this.lastUserMessageAt) || other.lastUserMessageAt == _this.lastUserMessageAt)&&(identical(other.archived, _this.archived) || other.archived == _this.archived));
}


@override
int get hashCode {
  final _this = this as WorkspaceThreadRecord;
  return Object.hash(runtimeType,_this.id,_this.projectId,_this.title,_this.mode,_this.delegationMode,_this.delegationPreference,_this.frozenModel,_this.workspaceMode,_this.workspacePath,_this.rootThreadId,_this.parentThreadId,_this.role,_this.agentPath,_this.status,_this.createdAt,_this.updatedAt,_this.lastUserMessageAt,_this.archived);
}



}

/// @nodoc
abstract mixin class $WorkspaceThreadRecordCopyWith<$Res>  {
  factory $WorkspaceThreadRecordCopyWith(WorkspaceThreadRecord value, $Res Function(WorkspaceThreadRecord) _then) = _$WorkspaceThreadRecordCopyWithImpl;
@useResult
$Res call({
 String id, String projectId, String title, ThreadModeId mode, DelegationMode delegationMode, DelegationPreference delegationPreference, ModelSelection? frozenModel, ThreadWorkspaceMode workspaceMode, String workspacePath, String rootThreadId, String? parentThreadId, String role, String agentPath, ThreadStatus status, int createdAt, int updatedAt, int? lastUserMessageAt, bool archived
});


$ModelSelectionCopyWith<$Res>? get frozenModel;

}
/// @nodoc
class _$WorkspaceThreadRecordCopyWithImpl<$Res>
    implements $WorkspaceThreadRecordCopyWith<$Res> {
  _$WorkspaceThreadRecordCopyWithImpl(this._self, this._then);

  final WorkspaceThreadRecord _self;
  final $Res Function(WorkspaceThreadRecord) _then;

/// Create a copy of WorkspaceThreadRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? projectId = null,Object? title = null,Object? mode = null,Object? delegationMode = null,Object? delegationPreference = null,Object? frozenModel = freezed,Object? workspaceMode = null,Object? workspacePath = null,Object? rootThreadId = null,Object? parentThreadId = freezed,Object? role = null,Object? agentPath = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,Object? lastUserMessageAt = freezed,Object? archived = null,}) {
  return _then(WorkspaceThreadRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ThreadModeId,delegationMode: null == delegationMode ? _self.delegationMode : delegationMode // ignore: cast_nullable_to_non_nullable
as DelegationMode,delegationPreference: null == delegationPreference ? _self.delegationPreference : delegationPreference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,frozenModel: freezed == frozenModel ? _self.frozenModel : frozenModel // ignore: cast_nullable_to_non_nullable
as ModelSelection?,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as ThreadWorkspaceMode,workspacePath: null == workspacePath ? _self.workspacePath : workspacePath // ignore: cast_nullable_to_non_nullable
as String,rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as String,parentThreadId: freezed == parentThreadId ? _self.parentThreadId : parentThreadId // ignore: cast_nullable_to_non_nullable
as String?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,agentPath: null == agentPath ? _self.agentPath : agentPath // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastUserMessageAt: freezed == lastUserMessageAt ? _self.lastUserMessageAt : lastUserMessageAt // ignore: cast_nullable_to_non_nullable
as int?,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of WorkspaceThreadRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res>? get frozenModel {
    if (_self.frozenModel == null) {
    return null;
  }

  return $ModelSelectionCopyWith<$Res>(_self.frozenModel!, (value) {
    return _then(_self.copyWith(frozenModel: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkspaceThreadRecord].
extension WorkspaceThreadRecordPatterns on WorkspaceThreadRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceThreadRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceThreadRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceThreadRecord value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceThreadRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceThreadRecord value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceThreadRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String projectId,  String title,  ThreadModeId mode,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  ModelSelection? frozenModel,  ThreadWorkspaceMode workspaceMode,  String workspacePath,  String rootThreadId,  String? parentThreadId,  String role,  String agentPath,  ThreadStatus status,  int createdAt,  int updatedAt,  int? lastUserMessageAt,  bool archived)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceThreadRecord() when $default != null:
return $default(_that.id,_that.projectId,_that.title,_that.mode,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.workspaceMode,_that.workspacePath,_that.rootThreadId,_that.parentThreadId,_that.role,_that.agentPath,_that.status,_that.createdAt,_that.updatedAt,_that.lastUserMessageAt,_that.archived);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String projectId,  String title,  ThreadModeId mode,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  ModelSelection? frozenModel,  ThreadWorkspaceMode workspaceMode,  String workspacePath,  String rootThreadId,  String? parentThreadId,  String role,  String agentPath,  ThreadStatus status,  int createdAt,  int updatedAt,  int? lastUserMessageAt,  bool archived)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceThreadRecord():
return $default(_that.id,_that.projectId,_that.title,_that.mode,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.workspaceMode,_that.workspacePath,_that.rootThreadId,_that.parentThreadId,_that.role,_that.agentPath,_that.status,_that.createdAt,_that.updatedAt,_that.lastUserMessageAt,_that.archived);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String projectId,  String title,  ThreadModeId mode,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  ModelSelection? frozenModel,  ThreadWorkspaceMode workspaceMode,  String workspacePath,  String rootThreadId,  String? parentThreadId,  String role,  String agentPath,  ThreadStatus status,  int createdAt,  int updatedAt,  int? lastUserMessageAt,  bool archived)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceThreadRecord() when $default != null:
return $default(_that.id,_that.projectId,_that.title,_that.mode,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.workspaceMode,_that.workspacePath,_that.rootThreadId,_that.parentThreadId,_that.role,_that.agentPath,_that.status,_that.createdAt,_that.updatedAt,_that.lastUserMessageAt,_that.archived);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceThreadRecord extends WorkspaceThreadRecord {
  const _WorkspaceThreadRecord({required this.id, required this.projectId, required this.title, required this.mode, required this.delegationMode, required this.delegationPreference, required this.frozenModel, required this.workspaceMode, required this.workspacePath, required this.rootThreadId, required this.parentThreadId, required this.role, required this.agentPath, required this.status, required this.createdAt, required this.updatedAt, required this.lastUserMessageAt, required this.archived}): super._();


@override final  String id;
@override final  String projectId;
@override final  String title;
@override final  ThreadModeId mode;
@override final  DelegationMode delegationMode;
@override final  DelegationPreference delegationPreference;
@override final  ModelSelection? frozenModel;
@override final  ThreadWorkspaceMode workspaceMode;
@override final  String workspacePath;
@override final  String rootThreadId;
@override final  String? parentThreadId;
@override final  String role;
@override final  String agentPath;
@override final  ThreadStatus status;
@override final  int createdAt;
@override final  int updatedAt;
@override final  int? lastUserMessageAt;
@override final  bool archived;

/// Create a copy of WorkspaceThreadRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceThreadRecordCopyWith<_WorkspaceThreadRecord> get copyWith => __$WorkspaceThreadRecordCopyWithImpl<_WorkspaceThreadRecord>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceThreadRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.title, title) || other.title == title)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.delegationMode, delegationMode) || other.delegationMode == delegationMode)&&(identical(other.delegationPreference, delegationPreference) || other.delegationPreference == delegationPreference)&&(identical(other.frozenModel, frozenModel) || other.frozenModel == frozenModel)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode)&&(identical(other.workspacePath, workspacePath) || other.workspacePath == workspacePath)&&(identical(other.rootThreadId, rootThreadId) || other.rootThreadId == rootThreadId)&&(identical(other.parentThreadId, parentThreadId) || other.parentThreadId == parentThreadId)&&(identical(other.role, role) || other.role == role)&&(identical(other.agentPath, agentPath) || other.agentPath == agentPath)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastUserMessageAt, lastUserMessageAt) || other.lastUserMessageAt == lastUserMessageAt)&&(identical(other.archived, archived) || other.archived == archived));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,projectId,title,mode,delegationMode,delegationPreference,frozenModel,workspaceMode,workspacePath,rootThreadId,parentThreadId,role,agentPath,status,createdAt,updatedAt,lastUserMessageAt,archived);
}



}

/// @nodoc
abstract mixin class _$WorkspaceThreadRecordCopyWith<$Res> implements $WorkspaceThreadRecordCopyWith<$Res> {
  factory _$WorkspaceThreadRecordCopyWith(_WorkspaceThreadRecord value, $Res Function(_WorkspaceThreadRecord) _then) = __$WorkspaceThreadRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, String projectId, String title, ThreadModeId mode, DelegationMode delegationMode, DelegationPreference delegationPreference, ModelSelection? frozenModel, ThreadWorkspaceMode workspaceMode, String workspacePath, String rootThreadId, String? parentThreadId, String role, String agentPath, ThreadStatus status, int createdAt, int updatedAt, int? lastUserMessageAt, bool archived
});


@override $ModelSelectionCopyWith<$Res>? get frozenModel;

}
/// @nodoc
class __$WorkspaceThreadRecordCopyWithImpl<$Res>
    implements _$WorkspaceThreadRecordCopyWith<$Res> {
  __$WorkspaceThreadRecordCopyWithImpl(this._self, this._then);

  final _WorkspaceThreadRecord _self;
  final $Res Function(_WorkspaceThreadRecord) _then;

/// Create a copy of WorkspaceThreadRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? projectId = null,Object? title = null,Object? mode = null,Object? delegationMode = null,Object? delegationPreference = null,Object? frozenModel = freezed,Object? workspaceMode = null,Object? workspacePath = null,Object? rootThreadId = null,Object? parentThreadId = freezed,Object? role = null,Object? agentPath = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,Object? lastUserMessageAt = freezed,Object? archived = null,}) {
  return _then(_WorkspaceThreadRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ThreadModeId,delegationMode: null == delegationMode ? _self.delegationMode : delegationMode // ignore: cast_nullable_to_non_nullable
as DelegationMode,delegationPreference: null == delegationPreference ? _self.delegationPreference : delegationPreference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,frozenModel: freezed == frozenModel ? _self.frozenModel : frozenModel // ignore: cast_nullable_to_non_nullable
as ModelSelection?,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as ThreadWorkspaceMode,workspacePath: null == workspacePath ? _self.workspacePath : workspacePath // ignore: cast_nullable_to_non_nullable
as String,rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as String,parentThreadId: freezed == parentThreadId ? _self.parentThreadId : parentThreadId // ignore: cast_nullable_to_non_nullable
as String?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,agentPath: null == agentPath ? _self.agentPath : agentPath // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastUserMessageAt: freezed == lastUserMessageAt ? _self.lastUserMessageAt : lastUserMessageAt // ignore: cast_nullable_to_non_nullable
as int?,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of WorkspaceThreadRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res>? get frozenModel {
    if (_self.frozenModel == null) {
    return null;
  }

  return $ModelSelectionCopyWith<$Res>(_self.frozenModel!, (value) {
    return _then(_self.copyWith(frozenModel: value));
  });
}
}

/// @nodoc
mixin _$AgentBudgetPause {

 String get turnId; BudgetLimitSnapshot get limit; int get pausedAt;
/// Create a copy of AgentBudgetPause
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentBudgetPauseCopyWith<AgentBudgetPause> get copyWith => _$AgentBudgetPauseCopyWithImpl<AgentBudgetPause>(this as AgentBudgetPause, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentBudgetPause;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentBudgetPause&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId)&&(identical(other.limit, _this.limit) || other.limit == _this.limit)&&(identical(other.pausedAt, _this.pausedAt) || other.pausedAt == _this.pausedAt));
}


@override
int get hashCode {
  final _this = this as AgentBudgetPause;
  return Object.hash(runtimeType,_this.turnId,_this.limit,_this.pausedAt);
}

@override
String toString() {
  final _this = this as AgentBudgetPause;
  return 'AgentBudgetPause(turnId: ${_this.turnId}, limit: ${_this.limit}, pausedAt: ${_this.pausedAt})';
}


}

/// @nodoc
abstract mixin class $AgentBudgetPauseCopyWith<$Res>  {
  factory $AgentBudgetPauseCopyWith(AgentBudgetPause value, $Res Function(AgentBudgetPause) _then) = _$AgentBudgetPauseCopyWithImpl;
@useResult
$Res call({
 String turnId, BudgetLimitSnapshot limit, int pausedAt
});


$BudgetLimitSnapshotCopyWith<$Res> get limit;

}
/// @nodoc
class _$AgentBudgetPauseCopyWithImpl<$Res>
    implements $AgentBudgetPauseCopyWith<$Res> {
  _$AgentBudgetPauseCopyWithImpl(this._self, this._then);

  final AgentBudgetPause _self;
  final $Res Function(AgentBudgetPause) _then;

/// Create a copy of AgentBudgetPause
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? turnId = null,Object? limit = null,Object? pausedAt = null,}) {
  return _then(AgentBudgetPause(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as BudgetLimitSnapshot,pausedAt: null == pausedAt ? _self.pausedAt : pausedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AgentBudgetPause
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BudgetLimitSnapshotCopyWith<$Res> get limit {

  return $BudgetLimitSnapshotCopyWith<$Res>(_self.limit, (value) {
    return _then(_self.copyWith(limit: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentBudgetPause].
extension AgentBudgetPausePatterns on AgentBudgetPause {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentBudgetPause value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentBudgetPause() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentBudgetPause value)  $default,){
final _that = this;
switch (_that) {
case _AgentBudgetPause():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentBudgetPause value)?  $default,){
final _that = this;
switch (_that) {
case _AgentBudgetPause() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String turnId,  BudgetLimitSnapshot limit,  int pausedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentBudgetPause() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String turnId,  BudgetLimitSnapshot limit,  int pausedAt)  $default,) {final _that = this;
switch (_that) {
case _AgentBudgetPause():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String turnId,  BudgetLimitSnapshot limit,  int pausedAt)?  $default,) {final _that = this;
switch (_that) {
case _AgentBudgetPause() when $default != null:
return $default(_that.turnId,_that.limit,_that.pausedAt);case _:
  return null;

}
}

}

/// @nodoc


class _AgentBudgetPause implements AgentBudgetPause {
  const _AgentBudgetPause({required this.turnId, required this.limit, required this.pausedAt});


@override final  String turnId;
@override final  BudgetLimitSnapshot limit;
@override final  int pausedAt;

/// Create a copy of AgentBudgetPause
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentBudgetPauseCopyWith<_AgentBudgetPause> get copyWith => __$AgentBudgetPauseCopyWithImpl<_AgentBudgetPause>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentBudgetPause&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.limit, limit) || other.limit == limit)&&(identical(other.pausedAt, pausedAt) || other.pausedAt == pausedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId,limit,pausedAt);
}

@override
String toString() {
    return 'AgentBudgetPause(turnId: $turnId, limit: $limit, pausedAt: $pausedAt)';
}


}

/// @nodoc
abstract mixin class _$AgentBudgetPauseCopyWith<$Res> implements $AgentBudgetPauseCopyWith<$Res> {
  factory _$AgentBudgetPauseCopyWith(_AgentBudgetPause value, $Res Function(_AgentBudgetPause) _then) = __$AgentBudgetPauseCopyWithImpl;
@override @useResult
$Res call({
 String turnId, BudgetLimitSnapshot limit, int pausedAt
});


@override $BudgetLimitSnapshotCopyWith<$Res> get limit;

}
/// @nodoc
class __$AgentBudgetPauseCopyWithImpl<$Res>
    implements _$AgentBudgetPauseCopyWith<$Res> {
  __$AgentBudgetPauseCopyWithImpl(this._self, this._then);

  final _AgentBudgetPause _self;
  final $Res Function(_AgentBudgetPause) _then;

/// Create a copy of AgentBudgetPause
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? turnId = null,Object? limit = null,Object? pausedAt = null,}) {
  return _then(_AgentBudgetPause(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as BudgetLimitSnapshot,pausedAt: null == pausedAt ? _self.pausedAt : pausedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AgentBudgetPause
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
mixin _$AgentState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentState);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AgentStateCopyWith<$Res>  {
$AgentStateCopyWith(AgentState _, $Res Function(AgentState) __);
}


/// Adds pattern-matching-related methods to [AgentState].
extension AgentStatePatterns on AgentState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IdleAgentState value)?  idle,TResult Function( QueuedAgentState value)?  queued,TResult Function( RunningAgentState value)?  running,TResult Function( WaitingToolAgentState value)?  waitingTool,TResult Function( WaitingInteractionAgentState value)?  waitingInteraction,TResult Function( CancellingAgentState value)?  cancelling,TResult Function( ClosingAgentState value)?  closing,TResult Function( ClosedAgentState value)?  closed,TResult Function( FaultedAgentState value)?  faulted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IdleAgentState() when idle != null:
return idle(_that);case QueuedAgentState() when queued != null:
return queued(_that);case RunningAgentState() when running != null:
return running(_that);case WaitingToolAgentState() when waitingTool != null:
return waitingTool(_that);case WaitingInteractionAgentState() when waitingInteraction != null:
return waitingInteraction(_that);case CancellingAgentState() when cancelling != null:
return cancelling(_that);case ClosingAgentState() when closing != null:
return closing(_that);case ClosedAgentState() when closed != null:
return closed(_that);case FaultedAgentState() when faulted != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IdleAgentState value)  idle,required TResult Function( QueuedAgentState value)  queued,required TResult Function( RunningAgentState value)  running,required TResult Function( WaitingToolAgentState value)  waitingTool,required TResult Function( WaitingInteractionAgentState value)  waitingInteraction,required TResult Function( CancellingAgentState value)  cancelling,required TResult Function( ClosingAgentState value)  closing,required TResult Function( ClosedAgentState value)  closed,required TResult Function( FaultedAgentState value)  faulted,}){
final _that = this;
switch (_that) {
case IdleAgentState():
return idle(_that);case QueuedAgentState():
return queued(_that);case RunningAgentState():
return running(_that);case WaitingToolAgentState():
return waitingTool(_that);case WaitingInteractionAgentState():
return waitingInteraction(_that);case CancellingAgentState():
return cancelling(_that);case ClosingAgentState():
return closing(_that);case ClosedAgentState():
return closed(_that);case FaultedAgentState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IdleAgentState value)?  idle,TResult? Function( QueuedAgentState value)?  queued,TResult? Function( RunningAgentState value)?  running,TResult? Function( WaitingToolAgentState value)?  waitingTool,TResult? Function( WaitingInteractionAgentState value)?  waitingInteraction,TResult? Function( CancellingAgentState value)?  cancelling,TResult? Function( ClosingAgentState value)?  closing,TResult? Function( ClosedAgentState value)?  closed,TResult? Function( FaultedAgentState value)?  faulted,}){
final _that = this;
switch (_that) {
case IdleAgentState() when idle != null:
return idle(_that);case QueuedAgentState() when queued != null:
return queued(_that);case RunningAgentState() when running != null:
return running(_that);case WaitingToolAgentState() when waitingTool != null:
return waitingTool(_that);case WaitingInteractionAgentState() when waitingInteraction != null:
return waitingInteraction(_that);case CancellingAgentState() when cancelling != null:
return cancelling(_that);case ClosingAgentState() when closing != null:
return closing(_that);case ClosedAgentState() when closed != null:
return closed(_that);case FaultedAgentState() when faulted != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( AgentBudgetPause? budgetPause)?  idle,TResult Function( String turnId)?  queued,TResult Function( String turnId)?  running,TResult Function( String turnId)?  waitingTool,TResult Function( String turnId,  String interactionId)?  waitingInteraction,TResult Function( String turnId)?  cancelling,TResult Function( AgentWorkspaceDisposition workspaceDisposition,  String? turnId,  SourceStateError? error)?  closing,TResult Function()?  closed,TResult Function( SourceStateError error,  String? turnId,  AgentFaultClassification classification)?  faulted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IdleAgentState() when idle != null:
return idle(_that.budgetPause);case QueuedAgentState() when queued != null:
return queued(_that.turnId);case RunningAgentState() when running != null:
return running(_that.turnId);case WaitingToolAgentState() when waitingTool != null:
return waitingTool(_that.turnId);case WaitingInteractionAgentState() when waitingInteraction != null:
return waitingInteraction(_that.turnId,_that.interactionId);case CancellingAgentState() when cancelling != null:
return cancelling(_that.turnId);case ClosingAgentState() when closing != null:
return closing(_that.workspaceDisposition,_that.turnId,_that.error);case ClosedAgentState() when closed != null:
return closed();case FaultedAgentState() when faulted != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( AgentBudgetPause? budgetPause)  idle,required TResult Function( String turnId)  queued,required TResult Function( String turnId)  running,required TResult Function( String turnId)  waitingTool,required TResult Function( String turnId,  String interactionId)  waitingInteraction,required TResult Function( String turnId)  cancelling,required TResult Function( AgentWorkspaceDisposition workspaceDisposition,  String? turnId,  SourceStateError? error)  closing,required TResult Function()  closed,required TResult Function( SourceStateError error,  String? turnId,  AgentFaultClassification classification)  faulted,}) {final _that = this;
switch (_that) {
case IdleAgentState():
return idle(_that.budgetPause);case QueuedAgentState():
return queued(_that.turnId);case RunningAgentState():
return running(_that.turnId);case WaitingToolAgentState():
return waitingTool(_that.turnId);case WaitingInteractionAgentState():
return waitingInteraction(_that.turnId,_that.interactionId);case CancellingAgentState():
return cancelling(_that.turnId);case ClosingAgentState():
return closing(_that.workspaceDisposition,_that.turnId,_that.error);case ClosedAgentState():
return closed();case FaultedAgentState():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( AgentBudgetPause? budgetPause)?  idle,TResult? Function( String turnId)?  queued,TResult? Function( String turnId)?  running,TResult? Function( String turnId)?  waitingTool,TResult? Function( String turnId,  String interactionId)?  waitingInteraction,TResult? Function( String turnId)?  cancelling,TResult? Function( AgentWorkspaceDisposition workspaceDisposition,  String? turnId,  SourceStateError? error)?  closing,TResult? Function()?  closed,TResult? Function( SourceStateError error,  String? turnId,  AgentFaultClassification classification)?  faulted,}) {final _that = this;
switch (_that) {
case IdleAgentState() when idle != null:
return idle(_that.budgetPause);case QueuedAgentState() when queued != null:
return queued(_that.turnId);case RunningAgentState() when running != null:
return running(_that.turnId);case WaitingToolAgentState() when waitingTool != null:
return waitingTool(_that.turnId);case WaitingInteractionAgentState() when waitingInteraction != null:
return waitingInteraction(_that.turnId,_that.interactionId);case CancellingAgentState() when cancelling != null:
return cancelling(_that.turnId);case ClosingAgentState() when closing != null:
return closing(_that.workspaceDisposition,_that.turnId,_that.error);case ClosedAgentState() when closed != null:
return closed();case FaultedAgentState() when faulted != null:
return faulted(_that.error,_that.turnId,_that.classification);case _:
  return null;

}
}

}

/// @nodoc


class IdleAgentState implements AgentState {
  const IdleAgentState({required this.budgetPause});


 final  AgentBudgetPause? budgetPause;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IdleAgentStateCopyWith<IdleAgentState> get copyWith => _$IdleAgentStateCopyWithImpl<IdleAgentState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IdleAgentState&&(identical(other.budgetPause, budgetPause) || other.budgetPause == budgetPause));
}


@override
int get hashCode {
    return Object.hash(runtimeType,budgetPause);
}



}

/// @nodoc
abstract mixin class $IdleAgentStateCopyWith<$Res> implements $AgentStateCopyWith<$Res> {
  factory $IdleAgentStateCopyWith(IdleAgentState value, $Res Function(IdleAgentState) _then) = _$IdleAgentStateCopyWithImpl;
@useResult
$Res call({
 AgentBudgetPause? budgetPause
});


$AgentBudgetPauseCopyWith<$Res>? get budgetPause;

}
/// @nodoc
class _$IdleAgentStateCopyWithImpl<$Res>
    implements $IdleAgentStateCopyWith<$Res> {
  _$IdleAgentStateCopyWithImpl(this._self, this._then);

  final IdleAgentState _self;
  final $Res Function(IdleAgentState) _then;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? budgetPause = freezed,}) {
  return _then(IdleAgentState(
budgetPause: freezed == budgetPause ? _self.budgetPause : budgetPause // ignore: cast_nullable_to_non_nullable
as AgentBudgetPause?,
  ));
}

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentBudgetPauseCopyWith<$Res>? get budgetPause {
    if (_self.budgetPause == null) {
    return null;
  }

  return $AgentBudgetPauseCopyWith<$Res>(_self.budgetPause!, (value) {
    return _then(_self.copyWith(budgetPause: value));
  });
}
}

/// @nodoc


class QueuedAgentState implements AgentState {
  const QueuedAgentState({required this.turnId});


 final  String turnId;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueuedAgentStateCopyWith<QueuedAgentState> get copyWith => _$QueuedAgentStateCopyWithImpl<QueuedAgentState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueuedAgentState&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}



}

/// @nodoc
abstract mixin class $QueuedAgentStateCopyWith<$Res> implements $AgentStateCopyWith<$Res> {
  factory $QueuedAgentStateCopyWith(QueuedAgentState value, $Res Function(QueuedAgentState) _then) = _$QueuedAgentStateCopyWithImpl;
@useResult
$Res call({
 String turnId
});




}
/// @nodoc
class _$QueuedAgentStateCopyWithImpl<$Res>
    implements $QueuedAgentStateCopyWith<$Res> {
  _$QueuedAgentStateCopyWithImpl(this._self, this._then);

  final QueuedAgentState _self;
  final $Res Function(QueuedAgentState) _then;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(QueuedAgentState(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RunningAgentState implements AgentState {
  const RunningAgentState({required this.turnId});


 final  String turnId;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RunningAgentStateCopyWith<RunningAgentState> get copyWith => _$RunningAgentStateCopyWithImpl<RunningAgentState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RunningAgentState&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}



}

/// @nodoc
abstract mixin class $RunningAgentStateCopyWith<$Res> implements $AgentStateCopyWith<$Res> {
  factory $RunningAgentStateCopyWith(RunningAgentState value, $Res Function(RunningAgentState) _then) = _$RunningAgentStateCopyWithImpl;
@useResult
$Res call({
 String turnId
});




}
/// @nodoc
class _$RunningAgentStateCopyWithImpl<$Res>
    implements $RunningAgentStateCopyWith<$Res> {
  _$RunningAgentStateCopyWithImpl(this._self, this._then);

  final RunningAgentState _self;
  final $Res Function(RunningAgentState) _then;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(RunningAgentState(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class WaitingToolAgentState implements AgentState {
  const WaitingToolAgentState({required this.turnId});


 final  String turnId;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WaitingToolAgentStateCopyWith<WaitingToolAgentState> get copyWith => _$WaitingToolAgentStateCopyWithImpl<WaitingToolAgentState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is WaitingToolAgentState&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}



}

/// @nodoc
abstract mixin class $WaitingToolAgentStateCopyWith<$Res> implements $AgentStateCopyWith<$Res> {
  factory $WaitingToolAgentStateCopyWith(WaitingToolAgentState value, $Res Function(WaitingToolAgentState) _then) = _$WaitingToolAgentStateCopyWithImpl;
@useResult
$Res call({
 String turnId
});




}
/// @nodoc
class _$WaitingToolAgentStateCopyWithImpl<$Res>
    implements $WaitingToolAgentStateCopyWith<$Res> {
  _$WaitingToolAgentStateCopyWithImpl(this._self, this._then);

  final WaitingToolAgentState _self;
  final $Res Function(WaitingToolAgentState) _then;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(WaitingToolAgentState(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class WaitingInteractionAgentState implements AgentState {
  const WaitingInteractionAgentState({required this.turnId, required this.interactionId});


 final  String turnId;
 final  String interactionId;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WaitingInteractionAgentStateCopyWith<WaitingInteractionAgentState> get copyWith => _$WaitingInteractionAgentStateCopyWithImpl<WaitingInteractionAgentState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is WaitingInteractionAgentState&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.interactionId, interactionId) || other.interactionId == interactionId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId,interactionId);
}



}

/// @nodoc
abstract mixin class $WaitingInteractionAgentStateCopyWith<$Res> implements $AgentStateCopyWith<$Res> {
  factory $WaitingInteractionAgentStateCopyWith(WaitingInteractionAgentState value, $Res Function(WaitingInteractionAgentState) _then) = _$WaitingInteractionAgentStateCopyWithImpl;
@useResult
$Res call({
 String turnId, String interactionId
});




}
/// @nodoc
class _$WaitingInteractionAgentStateCopyWithImpl<$Res>
    implements $WaitingInteractionAgentStateCopyWith<$Res> {
  _$WaitingInteractionAgentStateCopyWithImpl(this._self, this._then);

  final WaitingInteractionAgentState _self;
  final $Res Function(WaitingInteractionAgentState) _then;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,Object? interactionId = null,}) {
  return _then(WaitingInteractionAgentState(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CancellingAgentState implements AgentState {
  const CancellingAgentState({required this.turnId});


 final  String turnId;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancellingAgentStateCopyWith<CancellingAgentState> get copyWith => _$CancellingAgentStateCopyWithImpl<CancellingAgentState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancellingAgentState&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}



}

/// @nodoc
abstract mixin class $CancellingAgentStateCopyWith<$Res> implements $AgentStateCopyWith<$Res> {
  factory $CancellingAgentStateCopyWith(CancellingAgentState value, $Res Function(CancellingAgentState) _then) = _$CancellingAgentStateCopyWithImpl;
@useResult
$Res call({
 String turnId
});




}
/// @nodoc
class _$CancellingAgentStateCopyWithImpl<$Res>
    implements $CancellingAgentStateCopyWith<$Res> {
  _$CancellingAgentStateCopyWithImpl(this._self, this._then);

  final CancellingAgentState _self;
  final $Res Function(CancellingAgentState) _then;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(CancellingAgentState(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ClosingAgentState implements AgentState {
  const ClosingAgentState({required this.workspaceDisposition, required this.turnId, required this.error});


 final  AgentWorkspaceDisposition workspaceDisposition;
 final  String? turnId;
 final  SourceStateError? error;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClosingAgentStateCopyWith<ClosingAgentState> get copyWith => _$ClosingAgentStateCopyWithImpl<ClosingAgentState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ClosingAgentState&&(identical(other.workspaceDisposition, workspaceDisposition) || other.workspaceDisposition == workspaceDisposition)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,workspaceDisposition,turnId,error);
}



}

/// @nodoc
abstract mixin class $ClosingAgentStateCopyWith<$Res> implements $AgentStateCopyWith<$Res> {
  factory $ClosingAgentStateCopyWith(ClosingAgentState value, $Res Function(ClosingAgentState) _then) = _$ClosingAgentStateCopyWithImpl;
@useResult
$Res call({
 AgentWorkspaceDisposition workspaceDisposition, String? turnId, SourceStateError? error
});


$SourceStateErrorCopyWith<$Res>? get error;

}
/// @nodoc
class _$ClosingAgentStateCopyWithImpl<$Res>
    implements $ClosingAgentStateCopyWith<$Res> {
  _$ClosingAgentStateCopyWithImpl(this._self, this._then);

  final ClosingAgentState _self;
  final $Res Function(ClosingAgentState) _then;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? workspaceDisposition = null,Object? turnId = freezed,Object? error = freezed,}) {
  return _then(ClosingAgentState(
workspaceDisposition: null == workspaceDisposition ? _self.workspaceDisposition : workspaceDisposition // ignore: cast_nullable_to_non_nullable
as AgentWorkspaceDisposition,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError?,
  ));
}

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $SourceStateErrorCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class ClosedAgentState implements AgentState {
  const ClosedAgentState();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ClosedAgentState);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class FaultedAgentState implements AgentState {
  const FaultedAgentState({required this.error, required this.turnId, required this.classification});


 final  SourceStateError error;
 final  String? turnId;
 final  AgentFaultClassification classification;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FaultedAgentStateCopyWith<FaultedAgentState> get copyWith => _$FaultedAgentStateCopyWithImpl<FaultedAgentState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FaultedAgentState&&(identical(other.error, error) || other.error == error)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.classification, classification) || other.classification == classification));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error,turnId,classification);
}



}

/// @nodoc
abstract mixin class $FaultedAgentStateCopyWith<$Res> implements $AgentStateCopyWith<$Res> {
  factory $FaultedAgentStateCopyWith(FaultedAgentState value, $Res Function(FaultedAgentState) _then) = _$FaultedAgentStateCopyWithImpl;
@useResult
$Res call({
 SourceStateError error, String? turnId, AgentFaultClassification classification
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$FaultedAgentStateCopyWithImpl<$Res>
    implements $FaultedAgentStateCopyWith<$Res> {
  _$FaultedAgentStateCopyWithImpl(this._self, this._then);

  final FaultedAgentState _self;
  final $Res Function(FaultedAgentState) _then;

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,Object? turnId = freezed,Object? classification = null,}) {
  return _then(FaultedAgentState(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String?,classification: null == classification ? _self.classification : classification // ignore: cast_nullable_to_non_nullable
as AgentFaultClassification,
  ));
}

/// Create a copy of AgentState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res> get error {

  return $SourceStateErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$AgentDirectoryEntry {

 String get id; String get threadId; String get rootThreadId; String get path; String? get parentPath; String get role; DelegationMode get delegationMode; DelegationPreference get delegationPreference; ModelSelection? get frozenModel; String get task; String? get summary; int get depth; AgentState get state; int get updatedAt;
/// Create a copy of AgentDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryEntryCopyWith<AgentDirectoryEntry> get copyWith => _$AgentDirectoryEntryCopyWithImpl<AgentDirectoryEntry>(this as AgentDirectoryEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryEntry&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.rootThreadId, _this.rootThreadId) || other.rootThreadId == _this.rootThreadId)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.parentPath, _this.parentPath) || other.parentPath == _this.parentPath)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.delegationMode, _this.delegationMode) || other.delegationMode == _this.delegationMode)&&(identical(other.delegationPreference, _this.delegationPreference) || other.delegationPreference == _this.delegationPreference)&&(identical(other.frozenModel, _this.frozenModel) || other.frozenModel == _this.frozenModel)&&(identical(other.task, _this.task) || other.task == _this.task)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.depth, _this.depth) || other.depth == _this.depth)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryEntry;
  return Object.hash(runtimeType,_this.id,_this.threadId,_this.rootThreadId,_this.path,_this.parentPath,_this.role,_this.delegationMode,_this.delegationPreference,_this.frozenModel,_this.task,_this.summary,_this.depth,_this.state,_this.updatedAt);
}



}

/// @nodoc
abstract mixin class $AgentDirectoryEntryCopyWith<$Res>  {
  factory $AgentDirectoryEntryCopyWith(AgentDirectoryEntry value, $Res Function(AgentDirectoryEntry) _then) = _$AgentDirectoryEntryCopyWithImpl;
@useResult
$Res call({
 String id, String threadId, String rootThreadId, String path, String? parentPath, String role, DelegationMode delegationMode, DelegationPreference delegationPreference, ModelSelection? frozenModel, String task, String? summary, int depth, AgentState state, int updatedAt
});


$ModelSelectionCopyWith<$Res>? get frozenModel;$AgentStateCopyWith<$Res> get state;

}
/// @nodoc
class _$AgentDirectoryEntryCopyWithImpl<$Res>
    implements $AgentDirectoryEntryCopyWith<$Res> {
  _$AgentDirectoryEntryCopyWithImpl(this._self, this._then);

  final AgentDirectoryEntry _self;
  final $Res Function(AgentDirectoryEntry) _then;

/// Create a copy of AgentDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? threadId = null,Object? rootThreadId = null,Object? path = null,Object? parentPath = freezed,Object? role = null,Object? delegationMode = null,Object? delegationPreference = null,Object? frozenModel = freezed,Object? task = null,Object? summary = freezed,Object? depth = null,Object? state = null,Object? updatedAt = null,}) {
  return _then(AgentDirectoryEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,parentPath: freezed == parentPath ? _self.parentPath : parentPath // ignore: cast_nullable_to_non_nullable
as String?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,delegationMode: null == delegationMode ? _self.delegationMode : delegationMode // ignore: cast_nullable_to_non_nullable
as DelegationMode,delegationPreference: null == delegationPreference ? _self.delegationPreference : delegationPreference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,frozenModel: freezed == frozenModel ? _self.frozenModel : frozenModel // ignore: cast_nullable_to_non_nullable
as ModelSelection?,task: null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as String,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,depth: null == depth ? _self.depth : depth // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AgentState,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AgentDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res>? get frozenModel {
    if (_self.frozenModel == null) {
    return null;
  }

  return $ModelSelectionCopyWith<$Res>(_self.frozenModel!, (value) {
    return _then(_self.copyWith(frozenModel: value));
  });
}/// Create a copy of AgentDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentStateCopyWith<$Res> get state {

  return $AgentStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentDirectoryEntry].
extension AgentDirectoryEntryPatterns on AgentDirectoryEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentDirectoryEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentDirectoryEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentDirectoryEntry value)  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentDirectoryEntry value)?  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String threadId,  String rootThreadId,  String path,  String? parentPath,  String role,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  ModelSelection? frozenModel,  String task,  String? summary,  int depth,  AgentState state,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentDirectoryEntry() when $default != null:
return $default(_that.id,_that.threadId,_that.rootThreadId,_that.path,_that.parentPath,_that.role,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.task,_that.summary,_that.depth,_that.state,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String threadId,  String rootThreadId,  String path,  String? parentPath,  String role,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  ModelSelection? frozenModel,  String task,  String? summary,  int depth,  AgentState state,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryEntry():
return $default(_that.id,_that.threadId,_that.rootThreadId,_that.path,_that.parentPath,_that.role,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.task,_that.summary,_that.depth,_that.state,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String threadId,  String rootThreadId,  String path,  String? parentPath,  String role,  DelegationMode delegationMode,  DelegationPreference delegationPreference,  ModelSelection? frozenModel,  String task,  String? summary,  int depth,  AgentState state,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryEntry() when $default != null:
return $default(_that.id,_that.threadId,_that.rootThreadId,_that.path,_that.parentPath,_that.role,_that.delegationMode,_that.delegationPreference,_that.frozenModel,_that.task,_that.summary,_that.depth,_that.state,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _AgentDirectoryEntry implements AgentDirectoryEntry {
  const _AgentDirectoryEntry({required this.id, required this.threadId, required this.rootThreadId, required this.path, required this.parentPath, required this.role, required this.delegationMode, required this.delegationPreference, required this.frozenModel, required this.task, required this.summary, required this.depth, required this.state, required this.updatedAt});


@override final  String id;
@override final  String threadId;
@override final  String rootThreadId;
@override final  String path;
@override final  String? parentPath;
@override final  String role;
@override final  DelegationMode delegationMode;
@override final  DelegationPreference delegationPreference;
@override final  ModelSelection? frozenModel;
@override final  String task;
@override final  String? summary;
@override final  int depth;
@override final  AgentState state;
@override final  int updatedAt;

/// Create a copy of AgentDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentDirectoryEntryCopyWith<_AgentDirectoryEntry> get copyWith => __$AgentDirectoryEntryCopyWithImpl<_AgentDirectoryEntry>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentDirectoryEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.rootThreadId, rootThreadId) || other.rootThreadId == rootThreadId)&&(identical(other.path, path) || other.path == path)&&(identical(other.parentPath, parentPath) || other.parentPath == parentPath)&&(identical(other.role, role) || other.role == role)&&(identical(other.delegationMode, delegationMode) || other.delegationMode == delegationMode)&&(identical(other.delegationPreference, delegationPreference) || other.delegationPreference == delegationPreference)&&(identical(other.frozenModel, frozenModel) || other.frozenModel == frozenModel)&&(identical(other.task, task) || other.task == task)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.depth, depth) || other.depth == depth)&&(identical(other.state, state) || other.state == state)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,threadId,rootThreadId,path,parentPath,role,delegationMode,delegationPreference,frozenModel,task,summary,depth,state,updatedAt);
}



}

/// @nodoc
abstract mixin class _$AgentDirectoryEntryCopyWith<$Res> implements $AgentDirectoryEntryCopyWith<$Res> {
  factory _$AgentDirectoryEntryCopyWith(_AgentDirectoryEntry value, $Res Function(_AgentDirectoryEntry) _then) = __$AgentDirectoryEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, String threadId, String rootThreadId, String path, String? parentPath, String role, DelegationMode delegationMode, DelegationPreference delegationPreference, ModelSelection? frozenModel, String task, String? summary, int depth, AgentState state, int updatedAt
});


@override $ModelSelectionCopyWith<$Res>? get frozenModel;@override $AgentStateCopyWith<$Res> get state;

}
/// @nodoc
class __$AgentDirectoryEntryCopyWithImpl<$Res>
    implements _$AgentDirectoryEntryCopyWith<$Res> {
  __$AgentDirectoryEntryCopyWithImpl(this._self, this._then);

  final _AgentDirectoryEntry _self;
  final $Res Function(_AgentDirectoryEntry) _then;

/// Create a copy of AgentDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? threadId = null,Object? rootThreadId = null,Object? path = null,Object? parentPath = freezed,Object? role = null,Object? delegationMode = null,Object? delegationPreference = null,Object? frozenModel = freezed,Object? task = null,Object? summary = freezed,Object? depth = null,Object? state = null,Object? updatedAt = null,}) {
  return _then(_AgentDirectoryEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,parentPath: freezed == parentPath ? _self.parentPath : parentPath // ignore: cast_nullable_to_non_nullable
as String?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,delegationMode: null == delegationMode ? _self.delegationMode : delegationMode // ignore: cast_nullable_to_non_nullable
as DelegationMode,delegationPreference: null == delegationPreference ? _self.delegationPreference : delegationPreference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,frozenModel: freezed == frozenModel ? _self.frozenModel : frozenModel // ignore: cast_nullable_to_non_nullable
as ModelSelection?,task: null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as String,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,depth: null == depth ? _self.depth : depth // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AgentState,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AgentDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res>? get frozenModel {
    if (_self.frozenModel == null) {
    return null;
  }

  return $ModelSelectionCopyWith<$Res>(_self.frozenModel!, (value) {
    return _then(_self.copyWith(frozenModel: value));
  });
}/// Create a copy of AgentDirectoryEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentStateCopyWith<$Res> get state {

  return $AgentStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

// dart format on
