// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'add_project_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AddProjectState {

 AddProjectStep get step; bool? get remote; String get rawSearch; String get localPathRaw; RemoteState get connections; SshServerRuntimeEntry? get selectedServer; bool get picking; bool get pending; bool get sealed; WorkspaceActionPresentation? get action; StudioFailure? get failure; StudioFailure? get authenticationFailure; bool get passwordUnavailable; SshConnectionSnapshot? get connection; WorkspaceOpenResult? get opened;
/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddProjectStateCopyWith<AddProjectState> get copyWith => _$AddProjectStateCopyWithImpl<AddProjectState>(this as AddProjectState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AddProjectState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddProjectState&&(identical(other.step, _this.step) || other.step == _this.step)&&(identical(other.remote, _this.remote) || other.remote == _this.remote)&&(identical(other.rawSearch, _this.rawSearch) || other.rawSearch == _this.rawSearch)&&(identical(other.localPathRaw, _this.localPathRaw) || other.localPathRaw == _this.localPathRaw)&&(identical(other.connections, _this.connections) || other.connections == _this.connections)&&(identical(other.selectedServer, _this.selectedServer) || other.selectedServer == _this.selectedServer)&&(identical(other.picking, _this.picking) || other.picking == _this.picking)&&(identical(other.pending, _this.pending) || other.pending == _this.pending)&&(identical(other.sealed, _this.sealed) || other.sealed == _this.sealed)&&(identical(other.action, _this.action) || other.action == _this.action)&&(identical(other.failure, _this.failure) || other.failure == _this.failure)&&(identical(other.authenticationFailure, _this.authenticationFailure) || other.authenticationFailure == _this.authenticationFailure)&&(identical(other.passwordUnavailable, _this.passwordUnavailable) || other.passwordUnavailable == _this.passwordUnavailable)&&(identical(other.connection, _this.connection) || other.connection == _this.connection)&&(identical(other.opened, _this.opened) || other.opened == _this.opened));
}


@override
int get hashCode {
  final _this = this as AddProjectState;
  return Object.hash(runtimeType,_this.step,_this.remote,_this.rawSearch,_this.localPathRaw,_this.connections,_this.selectedServer,_this.picking,_this.pending,_this.sealed,_this.action,_this.failure,_this.authenticationFailure,_this.passwordUnavailable,_this.connection,_this.opened);
}



}

/// @nodoc
abstract mixin class $AddProjectStateCopyWith<$Res>  {
  factory $AddProjectStateCopyWith(AddProjectState value, $Res Function(AddProjectState) _then) = _$AddProjectStateCopyWithImpl;
@useResult
$Res call({
 AddProjectStep step, bool? remote, String rawSearch, String localPathRaw, RemoteState connections, SshServerRuntimeEntry? selectedServer, bool picking, bool pending, bool sealed, WorkspaceActionPresentation? action, StudioFailure? failure, StudioFailure? authenticationFailure, bool passwordUnavailable, SshConnectionSnapshot? connection, WorkspaceOpenResult? opened
});


$RemoteStateCopyWith<$Res> get connections;$SshServerRuntimeEntryCopyWith<$Res>? get selectedServer;$WorkspaceActionPresentationCopyWith<$Res>? get action;$StudioFailureCopyWith<$Res>? get failure;$StudioFailureCopyWith<$Res>? get authenticationFailure;$SshConnectionSnapshotCopyWith<$Res>? get connection;$WorkspaceOpenResultCopyWith<$Res>? get opened;

}
/// @nodoc
class _$AddProjectStateCopyWithImpl<$Res>
    implements $AddProjectStateCopyWith<$Res> {
  _$AddProjectStateCopyWithImpl(this._self, this._then);

  final AddProjectState _self;
  final $Res Function(AddProjectState) _then;

/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? step = null,Object? remote = freezed,Object? rawSearch = null,Object? localPathRaw = null,Object? connections = null,Object? selectedServer = freezed,Object? picking = null,Object? pending = null,Object? sealed = null,Object? action = freezed,Object? failure = freezed,Object? authenticationFailure = freezed,Object? passwordUnavailable = null,Object? connection = freezed,Object? opened = freezed,}) {
  return _then(AddProjectState(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as AddProjectStep,remote: freezed == remote ? _self.remote : remote // ignore: cast_nullable_to_non_nullable
as bool?,rawSearch: null == rawSearch ? _self.rawSearch : rawSearch // ignore: cast_nullable_to_non_nullable
as String,localPathRaw: null == localPathRaw ? _self.localPathRaw : localPathRaw // ignore: cast_nullable_to_non_nullable
as String,connections: null == connections ? _self.connections : connections // ignore: cast_nullable_to_non_nullable
as RemoteState,selectedServer: freezed == selectedServer ? _self.selectedServer : selectedServer // ignore: cast_nullable_to_non_nullable
as SshServerRuntimeEntry?,picking: null == picking ? _self.picking : picking // ignore: cast_nullable_to_non_nullable
as bool,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,sealed: null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as bool,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as WorkspaceActionPresentation?,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StudioFailure?,authenticationFailure: freezed == authenticationFailure ? _self.authenticationFailure : authenticationFailure // ignore: cast_nullable_to_non_nullable
as StudioFailure?,passwordUnavailable: null == passwordUnavailable ? _self.passwordUnavailable : passwordUnavailable // ignore: cast_nullable_to_non_nullable
as bool,connection: freezed == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as SshConnectionSnapshot?,opened: freezed == opened ? _self.opened : opened // ignore: cast_nullable_to_non_nullable
as WorkspaceOpenResult?,
  ));
}
/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RemoteStateCopyWith<$Res> get connections {

  return $RemoteStateCopyWith<$Res>(_self.connections, (value) {
    return _then(_self.copyWith(connections: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshServerRuntimeEntryCopyWith<$Res>? get selectedServer {
    if (_self.selectedServer == null) {
    return null;
  }

  return $SshServerRuntimeEntryCopyWith<$Res>(_self.selectedServer!, (value) {
    return _then(_self.copyWith(selectedServer: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceActionPresentationCopyWith<$Res>? get action {
    if (_self.action == null) {
    return null;
  }

  return $WorkspaceActionPresentationCopyWith<$Res>(_self.action!, (value) {
    return _then(_self.copyWith(action: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get failure {
    if (_self.failure == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.failure!, (value) {
    return _then(_self.copyWith(failure: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get authenticationFailure {
    if (_self.authenticationFailure == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.authenticationFailure!, (value) {
    return _then(_self.copyWith(authenticationFailure: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshConnectionSnapshotCopyWith<$Res>? get connection {
    if (_self.connection == null) {
    return null;
  }

  return $SshConnectionSnapshotCopyWith<$Res>(_self.connection!, (value) {
    return _then(_self.copyWith(connection: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceOpenResultCopyWith<$Res>? get opened {
    if (_self.opened == null) {
    return null;
  }

  return $WorkspaceOpenResultCopyWith<$Res>(_self.opened!, (value) {
    return _then(_self.copyWith(opened: value));
  });
}
}


/// Adds pattern-matching-related methods to [AddProjectState].
extension AddProjectStatePatterns on AddProjectState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AddProjectState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AddProjectState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AddProjectState value)  $default,){
final _that = this;
switch (_that) {
case _AddProjectState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AddProjectState value)?  $default,){
final _that = this;
switch (_that) {
case _AddProjectState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AddProjectStep step,  bool? remote,  String rawSearch,  String localPathRaw,  RemoteState connections,  SshServerRuntimeEntry? selectedServer,  bool picking,  bool pending,  bool sealed,  WorkspaceActionPresentation? action,  StudioFailure? failure,  StudioFailure? authenticationFailure,  bool passwordUnavailable,  SshConnectionSnapshot? connection,  WorkspaceOpenResult? opened)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AddProjectState() when $default != null:
return $default(_that.step,_that.remote,_that.rawSearch,_that.localPathRaw,_that.connections,_that.selectedServer,_that.picking,_that.pending,_that.sealed,_that.action,_that.failure,_that.authenticationFailure,_that.passwordUnavailable,_that.connection,_that.opened);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AddProjectStep step,  bool? remote,  String rawSearch,  String localPathRaw,  RemoteState connections,  SshServerRuntimeEntry? selectedServer,  bool picking,  bool pending,  bool sealed,  WorkspaceActionPresentation? action,  StudioFailure? failure,  StudioFailure? authenticationFailure,  bool passwordUnavailable,  SshConnectionSnapshot? connection,  WorkspaceOpenResult? opened)  $default,) {final _that = this;
switch (_that) {
case _AddProjectState():
return $default(_that.step,_that.remote,_that.rawSearch,_that.localPathRaw,_that.connections,_that.selectedServer,_that.picking,_that.pending,_that.sealed,_that.action,_that.failure,_that.authenticationFailure,_that.passwordUnavailable,_that.connection,_that.opened);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AddProjectStep step,  bool? remote,  String rawSearch,  String localPathRaw,  RemoteState connections,  SshServerRuntimeEntry? selectedServer,  bool picking,  bool pending,  bool sealed,  WorkspaceActionPresentation? action,  StudioFailure? failure,  StudioFailure? authenticationFailure,  bool passwordUnavailable,  SshConnectionSnapshot? connection,  WorkspaceOpenResult? opened)?  $default,) {final _that = this;
switch (_that) {
case _AddProjectState() when $default != null:
return $default(_that.step,_that.remote,_that.rawSearch,_that.localPathRaw,_that.connections,_that.selectedServer,_that.picking,_that.pending,_that.sealed,_that.action,_that.failure,_that.authenticationFailure,_that.passwordUnavailable,_that.connection,_that.opened);case _:
  return null;

}
}

}

/// @nodoc


class _AddProjectState extends AddProjectState {
  const _AddProjectState({required this.step, required this.remote, required this.rawSearch, required this.localPathRaw, required this.connections, required this.selectedServer, required this.picking, required this.pending, required this.sealed, required this.action, required this.failure, required this.authenticationFailure, required this.passwordUnavailable, required this.connection, required this.opened}): super._();


@override final  AddProjectStep step;
@override final  bool? remote;
@override final  String rawSearch;
@override final  String localPathRaw;
@override final  RemoteState connections;
@override final  SshServerRuntimeEntry? selectedServer;
@override final  bool picking;
@override final  bool pending;
@override final  bool sealed;
@override final  WorkspaceActionPresentation? action;
@override final  StudioFailure? failure;
@override final  StudioFailure? authenticationFailure;
@override final  bool passwordUnavailable;
@override final  SshConnectionSnapshot? connection;
@override final  WorkspaceOpenResult? opened;

/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AddProjectStateCopyWith<_AddProjectState> get copyWith => __$AddProjectStateCopyWithImpl<_AddProjectState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AddProjectState&&(identical(other.step, step) || other.step == step)&&(identical(other.remote, remote) || other.remote == remote)&&(identical(other.rawSearch, rawSearch) || other.rawSearch == rawSearch)&&(identical(other.localPathRaw, localPathRaw) || other.localPathRaw == localPathRaw)&&(identical(other.connections, connections) || other.connections == connections)&&(identical(other.selectedServer, selectedServer) || other.selectedServer == selectedServer)&&(identical(other.picking, picking) || other.picking == picking)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.sealed, sealed) || other.sealed == sealed)&&(identical(other.action, action) || other.action == action)&&(identical(other.failure, failure) || other.failure == failure)&&(identical(other.authenticationFailure, authenticationFailure) || other.authenticationFailure == authenticationFailure)&&(identical(other.passwordUnavailable, passwordUnavailable) || other.passwordUnavailable == passwordUnavailable)&&(identical(other.connection, connection) || other.connection == connection)&&(identical(other.opened, opened) || other.opened == opened));
}


@override
int get hashCode {
    return Object.hash(runtimeType,step,remote,rawSearch,localPathRaw,connections,selectedServer,picking,pending,sealed,action,failure,authenticationFailure,passwordUnavailable,connection,opened);
}



}

/// @nodoc
abstract mixin class _$AddProjectStateCopyWith<$Res> implements $AddProjectStateCopyWith<$Res> {
  factory _$AddProjectStateCopyWith(_AddProjectState value, $Res Function(_AddProjectState) _then) = __$AddProjectStateCopyWithImpl;
@override @useResult
$Res call({
 AddProjectStep step, bool? remote, String rawSearch, String localPathRaw, RemoteState connections, SshServerRuntimeEntry? selectedServer, bool picking, bool pending, bool sealed, WorkspaceActionPresentation? action, StudioFailure? failure, StudioFailure? authenticationFailure, bool passwordUnavailable, SshConnectionSnapshot? connection, WorkspaceOpenResult? opened
});


@override $RemoteStateCopyWith<$Res> get connections;@override $SshServerRuntimeEntryCopyWith<$Res>? get selectedServer;@override $WorkspaceActionPresentationCopyWith<$Res>? get action;@override $StudioFailureCopyWith<$Res>? get failure;@override $StudioFailureCopyWith<$Res>? get authenticationFailure;@override $SshConnectionSnapshotCopyWith<$Res>? get connection;@override $WorkspaceOpenResultCopyWith<$Res>? get opened;

}
/// @nodoc
class __$AddProjectStateCopyWithImpl<$Res>
    implements _$AddProjectStateCopyWith<$Res> {
  __$AddProjectStateCopyWithImpl(this._self, this._then);

  final _AddProjectState _self;
  final $Res Function(_AddProjectState) _then;

/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? step = null,Object? remote = freezed,Object? rawSearch = null,Object? localPathRaw = null,Object? connections = null,Object? selectedServer = freezed,Object? picking = null,Object? pending = null,Object? sealed = null,Object? action = freezed,Object? failure = freezed,Object? authenticationFailure = freezed,Object? passwordUnavailable = null,Object? connection = freezed,Object? opened = freezed,}) {
  return _then(_AddProjectState(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as AddProjectStep,remote: freezed == remote ? _self.remote : remote // ignore: cast_nullable_to_non_nullable
as bool?,rawSearch: null == rawSearch ? _self.rawSearch : rawSearch // ignore: cast_nullable_to_non_nullable
as String,localPathRaw: null == localPathRaw ? _self.localPathRaw : localPathRaw // ignore: cast_nullable_to_non_nullable
as String,connections: null == connections ? _self.connections : connections // ignore: cast_nullable_to_non_nullable
as RemoteState,selectedServer: freezed == selectedServer ? _self.selectedServer : selectedServer // ignore: cast_nullable_to_non_nullable
as SshServerRuntimeEntry?,picking: null == picking ? _self.picking : picking // ignore: cast_nullable_to_non_nullable
as bool,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,sealed: null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as bool,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as WorkspaceActionPresentation?,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StudioFailure?,authenticationFailure: freezed == authenticationFailure ? _self.authenticationFailure : authenticationFailure // ignore: cast_nullable_to_non_nullable
as StudioFailure?,passwordUnavailable: null == passwordUnavailable ? _self.passwordUnavailable : passwordUnavailable // ignore: cast_nullable_to_non_nullable
as bool,connection: freezed == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as SshConnectionSnapshot?,opened: freezed == opened ? _self.opened : opened // ignore: cast_nullable_to_non_nullable
as WorkspaceOpenResult?,
  ));
}

/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RemoteStateCopyWith<$Res> get connections {

  return $RemoteStateCopyWith<$Res>(_self.connections, (value) {
    return _then(_self.copyWith(connections: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshServerRuntimeEntryCopyWith<$Res>? get selectedServer {
    if (_self.selectedServer == null) {
    return null;
  }

  return $SshServerRuntimeEntryCopyWith<$Res>(_self.selectedServer!, (value) {
    return _then(_self.copyWith(selectedServer: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceActionPresentationCopyWith<$Res>? get action {
    if (_self.action == null) {
    return null;
  }

  return $WorkspaceActionPresentationCopyWith<$Res>(_self.action!, (value) {
    return _then(_self.copyWith(action: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get failure {
    if (_self.failure == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.failure!, (value) {
    return _then(_self.copyWith(failure: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get authenticationFailure {
    if (_self.authenticationFailure == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.authenticationFailure!, (value) {
    return _then(_self.copyWith(authenticationFailure: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshConnectionSnapshotCopyWith<$Res>? get connection {
    if (_self.connection == null) {
    return null;
  }

  return $SshConnectionSnapshotCopyWith<$Res>(_self.connection!, (value) {
    return _then(_self.copyWith(connection: value));
  });
}/// Create a copy of AddProjectState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceOpenResultCopyWith<$Res>? get opened {
    if (_self.opened == null) {
    return null;
  }

  return $WorkspaceOpenResultCopyWith<$Res>(_self.opened!, (value) {
    return _then(_self.copyWith(opened: value));
  });
}
}

// dart format on
