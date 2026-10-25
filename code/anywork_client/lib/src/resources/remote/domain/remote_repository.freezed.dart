// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'remote_repository.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RemoteState {

 List<SshServerRuntimeEntry>? get servers; Map<String, SshConnectionSnapshot> get connections;
/// Create a copy of RemoteState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteStateCopyWith<RemoteState> get copyWith => _$RemoteStateCopyWithImpl<RemoteState>(this as RemoteState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RemoteState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteState&&const DeepCollectionEquality().equals(other.servers, _this.servers)&&const DeepCollectionEquality().equals(other.connections, _this.connections));
}


@override
int get hashCode {
  final _this = this as RemoteState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.servers),const DeepCollectionEquality().hash(_this.connections));
}



}

/// @nodoc
abstract mixin class $RemoteStateCopyWith<$Res>  {
  factory $RemoteStateCopyWith(RemoteState value, $Res Function(RemoteState) _then) = _$RemoteStateCopyWithImpl;
@useResult
$Res call({
 List<SshServerRuntimeEntry>? servers, Map<String, SshConnectionSnapshot> connections
});




}
/// @nodoc
class _$RemoteStateCopyWithImpl<$Res>
    implements $RemoteStateCopyWith<$Res> {
  _$RemoteStateCopyWithImpl(this._self, this._then);

  final RemoteState _self;
  final $Res Function(RemoteState) _then;

/// Create a copy of RemoteState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? servers = freezed,Object? connections = null,}) {
  return _then(RemoteState(
servers: freezed == servers ? _self.servers : servers // ignore: cast_nullable_to_non_nullable
as List<SshServerRuntimeEntry>?,connections: null == connections ? _self.connections : connections // ignore: cast_nullable_to_non_nullable
as Map<String, SshConnectionSnapshot>,
  ));
}

}


/// Adds pattern-matching-related methods to [RemoteState].
extension RemoteStatePatterns on RemoteState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RemoteState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RemoteState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RemoteState value)  $default,){
final _that = this;
switch (_that) {
case _RemoteState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RemoteState value)?  $default,){
final _that = this;
switch (_that) {
case _RemoteState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<SshServerRuntimeEntry>? servers,  Map<String, SshConnectionSnapshot> connections)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RemoteState() when $default != null:
return $default(_that.servers,_that.connections);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<SshServerRuntimeEntry>? servers,  Map<String, SshConnectionSnapshot> connections)  $default,) {final _that = this;
switch (_that) {
case _RemoteState():
return $default(_that.servers,_that.connections);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<SshServerRuntimeEntry>? servers,  Map<String, SshConnectionSnapshot> connections)?  $default,) {final _that = this;
switch (_that) {
case _RemoteState() when $default != null:
return $default(_that.servers,_that.connections);case _:
  return null;

}
}

}

/// @nodoc


class _RemoteState implements RemoteState {
  const _RemoteState({required  List<SshServerRuntimeEntry>? servers, required  Map<String, SshConnectionSnapshot> connections}): _servers = servers,_connections = connections;


 final  List<SshServerRuntimeEntry>? _servers;
@override List<SshServerRuntimeEntry>? get servers {
  final value = _servers;
  if (value == null) return null;
  if (_servers is EqualUnmodifiableListView) return _servers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  Map<String, SshConnectionSnapshot> _connections;
@override Map<String, SshConnectionSnapshot> get connections {
  if (_connections is EqualUnmodifiableMapView) return _connections;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_connections);
}


/// Create a copy of RemoteState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RemoteStateCopyWith<_RemoteState> get copyWith => __$RemoteStateCopyWithImpl<_RemoteState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RemoteState&&const DeepCollectionEquality().equals(other.servers, _servers)&&const DeepCollectionEquality().equals(other.connections, _connections));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_servers),const DeepCollectionEquality().hash(_connections));
}



}

/// @nodoc
abstract mixin class _$RemoteStateCopyWith<$Res> implements $RemoteStateCopyWith<$Res> {
  factory _$RemoteStateCopyWith(_RemoteState value, $Res Function(_RemoteState) _then) = __$RemoteStateCopyWithImpl;
@override @useResult
$Res call({
 List<SshServerRuntimeEntry>? servers, Map<String, SshConnectionSnapshot> connections
});




}
/// @nodoc
class __$RemoteStateCopyWithImpl<$Res>
    implements _$RemoteStateCopyWith<$Res> {
  __$RemoteStateCopyWithImpl(this._self, this._then);

  final _RemoteState _self;
  final $Res Function(_RemoteState) _then;

/// Create a copy of RemoteState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? servers = freezed,Object? connections = null,}) {
  return _then(_RemoteState(
servers: freezed == servers ? _self._servers : servers // ignore: cast_nullable_to_non_nullable
as List<SshServerRuntimeEntry>?,connections: null == connections ? _self._connections : connections // ignore: cast_nullable_to_non_nullable
as Map<String, SshConnectionSnapshot>,
  ));
}


}

/// @nodoc
mixin _$RemoteDirectoryState {

 String get alias; String get path; String? get parent; List<RemoteDirectoryEntry> get entries; String? get nextCursor; bool get loading; StudioFailure? get error;
/// Create a copy of RemoteDirectoryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteDirectoryStateCopyWith<RemoteDirectoryState> get copyWith => _$RemoteDirectoryStateCopyWithImpl<RemoteDirectoryState>(this as RemoteDirectoryState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RemoteDirectoryState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteDirectoryState&&(identical(other.alias, _this.alias) || other.alias == _this.alias)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.parent, _this.parent) || other.parent == _this.parent)&&const DeepCollectionEquality().equals(other.entries, _this.entries)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as RemoteDirectoryState;
  return Object.hash(runtimeType,_this.alias,_this.path,_this.parent,const DeepCollectionEquality().hash(_this.entries),_this.nextCursor,_this.loading,_this.error);
}



}

/// @nodoc
abstract mixin class $RemoteDirectoryStateCopyWith<$Res>  {
  factory $RemoteDirectoryStateCopyWith(RemoteDirectoryState value, $Res Function(RemoteDirectoryState) _then) = _$RemoteDirectoryStateCopyWithImpl;
@useResult
$Res call({
 String alias, String path, String? parent, List<RemoteDirectoryEntry> entries, String? nextCursor, bool loading, StudioFailure? error
});


$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$RemoteDirectoryStateCopyWithImpl<$Res>
    implements $RemoteDirectoryStateCopyWith<$Res> {
  _$RemoteDirectoryStateCopyWithImpl(this._self, this._then);

  final RemoteDirectoryState _self;
  final $Res Function(RemoteDirectoryState) _then;

/// Create a copy of RemoteDirectoryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? alias = null,Object? path = null,Object? parent = freezed,Object? entries = null,Object? nextCursor = freezed,Object? loading = null,Object? error = freezed,}) {
  return _then(RemoteDirectoryState(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<RemoteDirectoryEntry>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of RemoteDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [RemoteDirectoryState].
extension RemoteDirectoryStatePatterns on RemoteDirectoryState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RemoteDirectoryState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RemoteDirectoryState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RemoteDirectoryState value)  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RemoteDirectoryState value)?  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String alias,  String path,  String? parent,  List<RemoteDirectoryEntry> entries,  String? nextCursor,  bool loading,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RemoteDirectoryState() when $default != null:
return $default(_that.alias,_that.path,_that.parent,_that.entries,_that.nextCursor,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String alias,  String path,  String? parent,  List<RemoteDirectoryEntry> entries,  String? nextCursor,  bool loading,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryState():
return $default(_that.alias,_that.path,_that.parent,_that.entries,_that.nextCursor,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String alias,  String path,  String? parent,  List<RemoteDirectoryEntry> entries,  String? nextCursor,  bool loading,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryState() when $default != null:
return $default(_that.alias,_that.path,_that.parent,_that.entries,_that.nextCursor,_that.loading,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _RemoteDirectoryState implements RemoteDirectoryState {
  const _RemoteDirectoryState({required this.alias, required this.path, required this.parent, required  List<RemoteDirectoryEntry> entries, required this.nextCursor, required this.loading, required this.error}): _entries = entries;


@override final  String alias;
@override final  String path;
@override final  String? parent;
 final  List<RemoteDirectoryEntry> _entries;
@override List<RemoteDirectoryEntry> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}

@override final  String? nextCursor;
@override final  bool loading;
@override final  StudioFailure? error;

/// Create a copy of RemoteDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RemoteDirectoryStateCopyWith<_RemoteDirectoryState> get copyWith => __$RemoteDirectoryStateCopyWithImpl<_RemoteDirectoryState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RemoteDirectoryState&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.path, path) || other.path == path)&&(identical(other.parent, parent) || other.parent == parent)&&const DeepCollectionEquality().equals(other.entries, _entries)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,alias,path,parent,const DeepCollectionEquality().hash(_entries),nextCursor,loading,error);
}



}

/// @nodoc
abstract mixin class _$RemoteDirectoryStateCopyWith<$Res> implements $RemoteDirectoryStateCopyWith<$Res> {
  factory _$RemoteDirectoryStateCopyWith(_RemoteDirectoryState value, $Res Function(_RemoteDirectoryState) _then) = __$RemoteDirectoryStateCopyWithImpl;
@override @useResult
$Res call({
 String alias, String path, String? parent, List<RemoteDirectoryEntry> entries, String? nextCursor, bool loading, StudioFailure? error
});


@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$RemoteDirectoryStateCopyWithImpl<$Res>
    implements _$RemoteDirectoryStateCopyWith<$Res> {
  __$RemoteDirectoryStateCopyWithImpl(this._self, this._then);

  final _RemoteDirectoryState _self;
  final $Res Function(_RemoteDirectoryState) _then;

/// Create a copy of RemoteDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? alias = null,Object? path = null,Object? parent = freezed,Object? entries = null,Object? nextCursor = freezed,Object? loading = null,Object? error = freezed,}) {
  return _then(_RemoteDirectoryState(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<RemoteDirectoryEntry>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of RemoteDirectoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
