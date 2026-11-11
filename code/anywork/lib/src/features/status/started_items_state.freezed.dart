// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'started_items_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StartedService {

 String get id; String get name; StartedServiceStatus get status; int? get percentage; String? get diagnostic; bool get canReconnect;
/// Create a copy of StartedService
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartedServiceCopyWith<StartedService> get copyWith => _$StartedServiceCopyWithImpl<StartedService>(this as StartedService, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartedService;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartedService&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.percentage, _this.percentage) || other.percentage == _this.percentage)&&(identical(other.diagnostic, _this.diagnostic) || other.diagnostic == _this.diagnostic)&&(identical(other.canReconnect, _this.canReconnect) || other.canReconnect == _this.canReconnect));
}


@override
int get hashCode {
  final _this = this as StartedService;
  return Object.hash(runtimeType,_this.id,_this.name,_this.status,_this.percentage,_this.diagnostic,_this.canReconnect);
}

@override
String toString() {
  final _this = this as StartedService;
  return 'StartedService(id: ${_this.id}, name: ${_this.name}, status: ${_this.status}, percentage: ${_this.percentage}, diagnostic: ${_this.diagnostic}, canReconnect: ${_this.canReconnect})';
}


}

/// @nodoc
abstract mixin class $StartedServiceCopyWith<$Res>  {
  factory $StartedServiceCopyWith(StartedService value, $Res Function(StartedService) _then) = _$StartedServiceCopyWithImpl;
@useResult
$Res call({
 String id, String name, StartedServiceStatus status, int? percentage, String? diagnostic, bool canReconnect
});




}
/// @nodoc
class _$StartedServiceCopyWithImpl<$Res>
    implements $StartedServiceCopyWith<$Res> {
  _$StartedServiceCopyWithImpl(this._self, this._then);

  final StartedService _self;
  final $Res Function(StartedService) _then;

/// Create a copy of StartedService
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? status = null,Object? percentage = freezed,Object? diagnostic = freezed,Object? canReconnect = null,}) {
  return _then(StartedService(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as StartedServiceStatus,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as int?,diagnostic: freezed == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as String?,canReconnect: null == canReconnect ? _self.canReconnect : canReconnect // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [StartedService].
extension StartedServicePatterns on StartedService {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartedService value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartedService() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartedService value)  $default,){
final _that = this;
switch (_that) {
case _StartedService():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartedService value)?  $default,){
final _that = this;
switch (_that) {
case _StartedService() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  StartedServiceStatus status,  int? percentage,  String? diagnostic,  bool canReconnect)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartedService() when $default != null:
return $default(_that.id,_that.name,_that.status,_that.percentage,_that.diagnostic,_that.canReconnect);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  StartedServiceStatus status,  int? percentage,  String? diagnostic,  bool canReconnect)  $default,) {final _that = this;
switch (_that) {
case _StartedService():
return $default(_that.id,_that.name,_that.status,_that.percentage,_that.diagnostic,_that.canReconnect);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  StartedServiceStatus status,  int? percentage,  String? diagnostic,  bool canReconnect)?  $default,) {final _that = this;
switch (_that) {
case _StartedService() when $default != null:
return $default(_that.id,_that.name,_that.status,_that.percentage,_that.diagnostic,_that.canReconnect);case _:
  return null;

}
}

}

/// @nodoc


class _StartedService implements StartedService {
  const _StartedService({required this.id, required this.name, required this.status, this.percentage, this.diagnostic, this.canReconnect = true});


@override final  String id;
@override final  String name;
@override final  StartedServiceStatus status;
@override final  int? percentage;
@override final  String? diagnostic;
@override@JsonKey() final  bool canReconnect;

/// Create a copy of StartedService
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartedServiceCopyWith<_StartedService> get copyWith => __$StartedServiceCopyWithImpl<_StartedService>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartedService&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.status, status) || other.status == status)&&(identical(other.percentage, percentage) || other.percentage == percentage)&&(identical(other.diagnostic, diagnostic) || other.diagnostic == diagnostic)&&(identical(other.canReconnect, canReconnect) || other.canReconnect == canReconnect));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,status,percentage,diagnostic,canReconnect);
}

@override
String toString() {
    return 'StartedService(id: $id, name: $name, status: $status, percentage: $percentage, diagnostic: $diagnostic, canReconnect: $canReconnect)';
}


}

/// @nodoc
abstract mixin class _$StartedServiceCopyWith<$Res> implements $StartedServiceCopyWith<$Res> {
  factory _$StartedServiceCopyWith(_StartedService value, $Res Function(_StartedService) _then) = __$StartedServiceCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, StartedServiceStatus status, int? percentage, String? diagnostic, bool canReconnect
});




}
/// @nodoc
class __$StartedServiceCopyWithImpl<$Res>
    implements _$StartedServiceCopyWith<$Res> {
  __$StartedServiceCopyWithImpl(this._self, this._then);

  final _StartedService _self;
  final $Res Function(_StartedService) _then;

/// Create a copy of StartedService
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? status = null,Object? percentage = freezed,Object? diagnostic = freezed,Object? canReconnect = null,}) {
  return _then(_StartedService(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as StartedServiceStatus,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as int?,diagnostic: freezed == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as String?,canReconnect: null == canReconnect ? _self.canReconnect : canReconnect // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$StartedItemsState {

 List<String> get skills; List<StartedService> get mcp; List<StartedService> get lsp; DomainSyncStatus get mcpSync; DomainSyncStatus get lspSync; Set<String> get pending; Map<String, String> get errors;
/// Create a copy of StartedItemsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartedItemsStateCopyWith<StartedItemsState> get copyWith => _$StartedItemsStateCopyWithImpl<StartedItemsState>(this as StartedItemsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartedItemsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartedItemsState&&const DeepCollectionEquality().equals(other.skills, _this.skills)&&const DeepCollectionEquality().equals(other.mcp, _this.mcp)&&const DeepCollectionEquality().equals(other.lsp, _this.lsp)&&(identical(other.mcpSync, _this.mcpSync) || other.mcpSync == _this.mcpSync)&&(identical(other.lspSync, _this.lspSync) || other.lspSync == _this.lspSync)&&const DeepCollectionEquality().equals(other.pending, _this.pending)&&const DeepCollectionEquality().equals(other.errors, _this.errors));
}


@override
int get hashCode {
  final _this = this as StartedItemsState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.skills),const DeepCollectionEquality().hash(_this.mcp),const DeepCollectionEquality().hash(_this.lsp),_this.mcpSync,_this.lspSync,const DeepCollectionEquality().hash(_this.pending),const DeepCollectionEquality().hash(_this.errors));
}

@override
String toString() {
  final _this = this as StartedItemsState;
  return 'StartedItemsState(skills: ${_this.skills}, mcp: ${_this.mcp}, lsp: ${_this.lsp}, mcpSync: ${_this.mcpSync}, lspSync: ${_this.lspSync}, pending: ${_this.pending}, errors: ${_this.errors})';
}


}

/// @nodoc
abstract mixin class $StartedItemsStateCopyWith<$Res>  {
  factory $StartedItemsStateCopyWith(StartedItemsState value, $Res Function(StartedItemsState) _then) = _$StartedItemsStateCopyWithImpl;
@useResult
$Res call({
 List<String> skills, List<StartedService> mcp, List<StartedService> lsp, DomainSyncStatus mcpSync, DomainSyncStatus lspSync, Set<String> pending, Map<String, String> errors
});




}
/// @nodoc
class _$StartedItemsStateCopyWithImpl<$Res>
    implements $StartedItemsStateCopyWith<$Res> {
  _$StartedItemsStateCopyWithImpl(this._self, this._then);

  final StartedItemsState _self;
  final $Res Function(StartedItemsState) _then;

/// Create a copy of StartedItemsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? skills = null,Object? mcp = null,Object? lsp = null,Object? mcpSync = null,Object? lspSync = null,Object? pending = null,Object? errors = null,}) {
  return _then(StartedItemsState(
skills: null == skills ? _self.skills : skills // ignore: cast_nullable_to_non_nullable
as List<String>,mcp: null == mcp ? _self.mcp : mcp // ignore: cast_nullable_to_non_nullable
as List<StartedService>,lsp: null == lsp ? _self.lsp : lsp // ignore: cast_nullable_to_non_nullable
as List<StartedService>,mcpSync: null == mcpSync ? _self.mcpSync : mcpSync // ignore: cast_nullable_to_non_nullable
as DomainSyncStatus,lspSync: null == lspSync ? _self.lspSync : lspSync // ignore: cast_nullable_to_non_nullable
as DomainSyncStatus,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as Set<String>,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

}


/// Adds pattern-matching-related methods to [StartedItemsState].
extension StartedItemsStatePatterns on StartedItemsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartedItemsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartedItemsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartedItemsState value)  $default,){
final _that = this;
switch (_that) {
case _StartedItemsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartedItemsState value)?  $default,){
final _that = this;
switch (_that) {
case _StartedItemsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<String> skills,  List<StartedService> mcp,  List<StartedService> lsp,  DomainSyncStatus mcpSync,  DomainSyncStatus lspSync,  Set<String> pending,  Map<String, String> errors)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartedItemsState() when $default != null:
return $default(_that.skills,_that.mcp,_that.lsp,_that.mcpSync,_that.lspSync,_that.pending,_that.errors);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<String> skills,  List<StartedService> mcp,  List<StartedService> lsp,  DomainSyncStatus mcpSync,  DomainSyncStatus lspSync,  Set<String> pending,  Map<String, String> errors)  $default,) {final _that = this;
switch (_that) {
case _StartedItemsState():
return $default(_that.skills,_that.mcp,_that.lsp,_that.mcpSync,_that.lspSync,_that.pending,_that.errors);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<String> skills,  List<StartedService> mcp,  List<StartedService> lsp,  DomainSyncStatus mcpSync,  DomainSyncStatus lspSync,  Set<String> pending,  Map<String, String> errors)?  $default,) {final _that = this;
switch (_that) {
case _StartedItemsState() when $default != null:
return $default(_that.skills,_that.mcp,_that.lsp,_that.mcpSync,_that.lspSync,_that.pending,_that.errors);case _:
  return null;

}
}

}

/// @nodoc


class _StartedItemsState implements StartedItemsState {
  const _StartedItemsState({ List<String> skills = const <String>[],  List<StartedService> mcp = const <StartedService>[],  List<StartedService> lsp = const <StartedService>[], required this.mcpSync, required this.lspSync,  Set<String> pending = const <String>{},  Map<String, String> errors = const <String, String>{}}): _skills = skills,_mcp = mcp,_lsp = lsp,_pending = pending,_errors = errors;


 final  List<String> _skills;
@override@JsonKey() List<String> get skills {
  if (_skills is EqualUnmodifiableListView) return _skills;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_skills);
}

 final  List<StartedService> _mcp;
@override@JsonKey() List<StartedService> get mcp {
  if (_mcp is EqualUnmodifiableListView) return _mcp;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mcp);
}

 final  List<StartedService> _lsp;
@override@JsonKey() List<StartedService> get lsp {
  if (_lsp is EqualUnmodifiableListView) return _lsp;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_lsp);
}

@override final  DomainSyncStatus mcpSync;
@override final  DomainSyncStatus lspSync;
 final  Set<String> _pending;
@override@JsonKey() Set<String> get pending {
  if (_pending is EqualUnmodifiableSetView) return _pending;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_pending);
}

 final  Map<String, String> _errors;
@override@JsonKey() Map<String, String> get errors {
  if (_errors is EqualUnmodifiableMapView) return _errors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_errors);
}


/// Create a copy of StartedItemsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartedItemsStateCopyWith<_StartedItemsState> get copyWith => __$StartedItemsStateCopyWithImpl<_StartedItemsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartedItemsState&&const DeepCollectionEquality().equals(other.skills, _skills)&&const DeepCollectionEquality().equals(other.mcp, _mcp)&&const DeepCollectionEquality().equals(other.lsp, _lsp)&&(identical(other.mcpSync, mcpSync) || other.mcpSync == mcpSync)&&(identical(other.lspSync, lspSync) || other.lspSync == lspSync)&&const DeepCollectionEquality().equals(other.pending, _pending)&&const DeepCollectionEquality().equals(other.errors, _errors));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_skills),const DeepCollectionEquality().hash(_mcp),const DeepCollectionEquality().hash(_lsp),mcpSync,lspSync,const DeepCollectionEquality().hash(_pending),const DeepCollectionEquality().hash(_errors));
}

@override
String toString() {
    return 'StartedItemsState(skills: $skills, mcp: $mcp, lsp: $lsp, mcpSync: $mcpSync, lspSync: $lspSync, pending: $pending, errors: $errors)';
}


}

/// @nodoc
abstract mixin class _$StartedItemsStateCopyWith<$Res> implements $StartedItemsStateCopyWith<$Res> {
  factory _$StartedItemsStateCopyWith(_StartedItemsState value, $Res Function(_StartedItemsState) _then) = __$StartedItemsStateCopyWithImpl;
@override @useResult
$Res call({
 List<String> skills, List<StartedService> mcp, List<StartedService> lsp, DomainSyncStatus mcpSync, DomainSyncStatus lspSync, Set<String> pending, Map<String, String> errors
});




}
/// @nodoc
class __$StartedItemsStateCopyWithImpl<$Res>
    implements _$StartedItemsStateCopyWith<$Res> {
  __$StartedItemsStateCopyWithImpl(this._self, this._then);

  final _StartedItemsState _self;
  final $Res Function(_StartedItemsState) _then;

/// Create a copy of StartedItemsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? skills = null,Object? mcp = null,Object? lsp = null,Object? mcpSync = null,Object? lspSync = null,Object? pending = null,Object? errors = null,}) {
  return _then(_StartedItemsState(
skills: null == skills ? _self._skills : skills // ignore: cast_nullable_to_non_nullable
as List<String>,mcp: null == mcp ? _self._mcp : mcp // ignore: cast_nullable_to_non_nullable
as List<StartedService>,lsp: null == lsp ? _self._lsp : lsp // ignore: cast_nullable_to_non_nullable
as List<StartedService>,mcpSync: null == mcpSync ? _self.mcpSync : mcpSync // ignore: cast_nullable_to_non_nullable
as DomainSyncStatus,lspSync: null == lspSync ? _self.lspSync : lspSync // ignore: cast_nullable_to_non_nullable
as DomainSyncStatus,pending: null == pending ? _self._pending : pending // ignore: cast_nullable_to_non_nullable
as Set<String>,errors: null == errors ? _self._errors : errors // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}

// dart format on
