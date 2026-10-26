// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ssh_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SshRowAction {

 SshRowOperation get kind; SettingsAction get action;
/// Create a copy of SshRowAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshRowActionCopyWith<SshRowAction> get copyWith => _$SshRowActionCopyWithImpl<SshRowAction>(this as SshRowAction, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SshRowAction;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshRowAction&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.action, _this.action) || other.action == _this.action));
}


@override
int get hashCode {
  final _this = this as SshRowAction;
  return Object.hash(runtimeType,_this.kind,_this.action);
}



}

/// @nodoc
abstract mixin class $SshRowActionCopyWith<$Res>  {
  factory $SshRowActionCopyWith(SshRowAction value, $Res Function(SshRowAction) _then) = _$SshRowActionCopyWithImpl;
@useResult
$Res call({
 SshRowOperation kind, SettingsAction action
});


$SettingsActionCopyWith<$Res> get action;

}
/// @nodoc
class _$SshRowActionCopyWithImpl<$Res>
    implements $SshRowActionCopyWith<$Res> {
  _$SshRowActionCopyWithImpl(this._self, this._then);

  final SshRowAction _self;
  final $Res Function(SshRowAction) _then;

/// Create a copy of SshRowAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? action = null,}) {
  return _then(SshRowAction(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as SshRowOperation,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction,
  ));
}
/// Create a copy of SshRowAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res> get action {

  return $SettingsActionCopyWith<$Res>(_self.action, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}


/// Adds pattern-matching-related methods to [SshRowAction].
extension SshRowActionPatterns on SshRowAction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SshRowAction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SshRowAction() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SshRowAction value)  $default,){
final _that = this;
switch (_that) {
case _SshRowAction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SshRowAction value)?  $default,){
final _that = this;
switch (_that) {
case _SshRowAction() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SshRowOperation kind,  SettingsAction action)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SshRowAction() when $default != null:
return $default(_that.kind,_that.action);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SshRowOperation kind,  SettingsAction action)  $default,) {final _that = this;
switch (_that) {
case _SshRowAction():
return $default(_that.kind,_that.action);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SshRowOperation kind,  SettingsAction action)?  $default,) {final _that = this;
switch (_that) {
case _SshRowAction() when $default != null:
return $default(_that.kind,_that.action);case _:
  return null;

}
}

}

/// @nodoc


class _SshRowAction implements SshRowAction {
  const _SshRowAction({required this.kind, required this.action});


@override final  SshRowOperation kind;
@override final  SettingsAction action;

/// Create a copy of SshRowAction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SshRowActionCopyWith<_SshRowAction> get copyWith => __$SshRowActionCopyWithImpl<_SshRowAction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SshRowAction&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.action, action) || other.action == action));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,action);
}



}

/// @nodoc
abstract mixin class _$SshRowActionCopyWith<$Res> implements $SshRowActionCopyWith<$Res> {
  factory _$SshRowActionCopyWith(_SshRowAction value, $Res Function(_SshRowAction) _then) = __$SshRowActionCopyWithImpl;
@override @useResult
$Res call({
 SshRowOperation kind, SettingsAction action
});


@override $SettingsActionCopyWith<$Res> get action;

}
/// @nodoc
class __$SshRowActionCopyWithImpl<$Res>
    implements _$SshRowActionCopyWith<$Res> {
  __$SshRowActionCopyWithImpl(this._self, this._then);

  final _SshRowAction _self;
  final $Res Function(_SshRowAction) _then;

/// Create a copy of SshRowAction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? action = null,}) {
  return _then(_SshRowAction(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as SshRowOperation,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction,
  ));
}

/// Create a copy of SshRowAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res> get action {

  return $SettingsActionCopyWith<$Res>(_self.action, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}

/// @nodoc
mixin _$SshPasswordChallenge {

 String get alias; int get intent; StudioFailure get error;
/// Create a copy of SshPasswordChallenge
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshPasswordChallengeCopyWith<SshPasswordChallenge> get copyWith => _$SshPasswordChallengeCopyWithImpl<SshPasswordChallenge>(this as SshPasswordChallenge, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SshPasswordChallenge;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshPasswordChallenge&&(identical(other.alias, _this.alias) || other.alias == _this.alias)&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as SshPasswordChallenge;
  return Object.hash(runtimeType,_this.alias,_this.intent,_this.error);
}



}

/// @nodoc
abstract mixin class $SshPasswordChallengeCopyWith<$Res>  {
  factory $SshPasswordChallengeCopyWith(SshPasswordChallenge value, $Res Function(SshPasswordChallenge) _then) = _$SshPasswordChallengeCopyWithImpl;
@useResult
$Res call({
 String alias, int intent, StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$SshPasswordChallengeCopyWithImpl<$Res>
    implements $SshPasswordChallengeCopyWith<$Res> {
  _$SshPasswordChallengeCopyWithImpl(this._self, this._then);

  final SshPasswordChallenge _self;
  final $Res Function(SshPasswordChallenge) _then;

/// Create a copy of SshPasswordChallenge
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? alias = null,Object? intent = null,Object? error = null,}) {
  return _then(SshPasswordChallenge(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}
/// Create a copy of SshPasswordChallenge
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [SshPasswordChallenge].
extension SshPasswordChallengePatterns on SshPasswordChallenge {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SshPasswordChallenge value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SshPasswordChallenge() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SshPasswordChallenge value)  $default,){
final _that = this;
switch (_that) {
case _SshPasswordChallenge():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SshPasswordChallenge value)?  $default,){
final _that = this;
switch (_that) {
case _SshPasswordChallenge() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String alias,  int intent,  StudioFailure error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SshPasswordChallenge() when $default != null:
return $default(_that.alias,_that.intent,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String alias,  int intent,  StudioFailure error)  $default,) {final _that = this;
switch (_that) {
case _SshPasswordChallenge():
return $default(_that.alias,_that.intent,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String alias,  int intent,  StudioFailure error)?  $default,) {final _that = this;
switch (_that) {
case _SshPasswordChallenge() when $default != null:
return $default(_that.alias,_that.intent,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _SshPasswordChallenge implements SshPasswordChallenge {
  const _SshPasswordChallenge({required this.alias, required this.intent, required this.error});


@override final  String alias;
@override final  int intent;
@override final  StudioFailure error;

/// Create a copy of SshPasswordChallenge
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SshPasswordChallengeCopyWith<_SshPasswordChallenge> get copyWith => __$SshPasswordChallengeCopyWithImpl<_SshPasswordChallenge>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SshPasswordChallenge&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,alias,intent,error);
}



}

/// @nodoc
abstract mixin class _$SshPasswordChallengeCopyWith<$Res> implements $SshPasswordChallengeCopyWith<$Res> {
  factory _$SshPasswordChallengeCopyWith(_SshPasswordChallenge value, $Res Function(_SshPasswordChallenge) _then) = __$SshPasswordChallengeCopyWithImpl;
@override @useResult
$Res call({
 String alias, int intent, StudioFailure error
});


@override $StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class __$SshPasswordChallengeCopyWithImpl<$Res>
    implements _$SshPasswordChallengeCopyWith<$Res> {
  __$SshPasswordChallengeCopyWithImpl(this._self, this._then);

  final _SshPasswordChallenge _self;
  final $Res Function(_SshPasswordChallenge) _then;

/// Create a copy of SshPasswordChallenge
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? alias = null,Object? intent = null,Object? error = null,}) {
  return _then(_SshPasswordChallenge(
alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of SshPasswordChallenge
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$SshViewState {

 RemoteState get source; Map<String, SshRowAction> get actions; int get latestIntent; SettingsAction? get reloadAction; SshEditorKey? get editor; String? get directoryAlias; int? get directoryDialogId; String? get passwordAlias; int? get passwordDialogId; int? get passwordScopeId; String? get deleteConfirmationAlias;
/// Create a copy of SshViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshViewStateCopyWith<SshViewState> get copyWith => _$SshViewStateCopyWithImpl<SshViewState>(this as SshViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SshViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshViewState&&(identical(other.source, _this.source) || other.source == _this.source)&&const DeepCollectionEquality().equals(other.actions, _this.actions)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&(identical(other.reloadAction, _this.reloadAction) || other.reloadAction == _this.reloadAction)&&(identical(other.editor, _this.editor) || other.editor == _this.editor)&&(identical(other.directoryAlias, _this.directoryAlias) || other.directoryAlias == _this.directoryAlias)&&(identical(other.directoryDialogId, _this.directoryDialogId) || other.directoryDialogId == _this.directoryDialogId)&&(identical(other.passwordAlias, _this.passwordAlias) || other.passwordAlias == _this.passwordAlias)&&(identical(other.passwordDialogId, _this.passwordDialogId) || other.passwordDialogId == _this.passwordDialogId)&&(identical(other.passwordScopeId, _this.passwordScopeId) || other.passwordScopeId == _this.passwordScopeId)&&(identical(other.deleteConfirmationAlias, _this.deleteConfirmationAlias) || other.deleteConfirmationAlias == _this.deleteConfirmationAlias));
}


@override
int get hashCode {
  final _this = this as SshViewState;
  return Object.hash(runtimeType,_this.source,const DeepCollectionEquality().hash(_this.actions),_this.latestIntent,_this.reloadAction,_this.editor,_this.directoryAlias,_this.directoryDialogId,_this.passwordAlias,_this.passwordDialogId,_this.passwordScopeId,_this.deleteConfirmationAlias);
}



}

/// @nodoc
abstract mixin class $SshViewStateCopyWith<$Res>  {
  factory $SshViewStateCopyWith(SshViewState value, $Res Function(SshViewState) _then) = _$SshViewStateCopyWithImpl;
@useResult
$Res call({
 RemoteState source, Map<String, SshRowAction> actions, int latestIntent, SettingsAction? reloadAction, SshEditorKey? editor, String? directoryAlias, int? directoryDialogId, String? passwordAlias, int? passwordDialogId, int? passwordScopeId, String? deleteConfirmationAlias
});


$RemoteStateCopyWith<$Res> get source;$SettingsActionCopyWith<$Res>? get reloadAction;$SshEditorKeyCopyWith<$Res>? get editor;

}
/// @nodoc
class _$SshViewStateCopyWithImpl<$Res>
    implements $SshViewStateCopyWith<$Res> {
  _$SshViewStateCopyWithImpl(this._self, this._then);

  final SshViewState _self;
  final $Res Function(SshViewState) _then;

/// Create a copy of SshViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? actions = null,Object? latestIntent = null,Object? reloadAction = freezed,Object? editor = freezed,Object? directoryAlias = freezed,Object? directoryDialogId = freezed,Object? passwordAlias = freezed,Object? passwordDialogId = freezed,Object? passwordScopeId = freezed,Object? deleteConfirmationAlias = freezed,}) {
  return _then(SshViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as RemoteState,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as Map<String, SshRowAction>,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,reloadAction: freezed == reloadAction ? _self.reloadAction : reloadAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,editor: freezed == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as SshEditorKey?,directoryAlias: freezed == directoryAlias ? _self.directoryAlias : directoryAlias // ignore: cast_nullable_to_non_nullable
as String?,directoryDialogId: freezed == directoryDialogId ? _self.directoryDialogId : directoryDialogId // ignore: cast_nullable_to_non_nullable
as int?,passwordAlias: freezed == passwordAlias ? _self.passwordAlias : passwordAlias // ignore: cast_nullable_to_non_nullable
as String?,passwordDialogId: freezed == passwordDialogId ? _self.passwordDialogId : passwordDialogId // ignore: cast_nullable_to_non_nullable
as int?,passwordScopeId: freezed == passwordScopeId ? _self.passwordScopeId : passwordScopeId // ignore: cast_nullable_to_non_nullable
as int?,deleteConfirmationAlias: freezed == deleteConfirmationAlias ? _self.deleteConfirmationAlias : deleteConfirmationAlias // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of SshViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RemoteStateCopyWith<$Res> get source {

  return $RemoteStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of SshViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get reloadAction {
    if (_self.reloadAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.reloadAction!, (value) {
    return _then(_self.copyWith(reloadAction: value));
  });
}/// Create a copy of SshViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshEditorKeyCopyWith<$Res>? get editor {
    if (_self.editor == null) {
    return null;
  }

  return $SshEditorKeyCopyWith<$Res>(_self.editor!, (value) {
    return _then(_self.copyWith(editor: value));
  });
}
}


/// Adds pattern-matching-related methods to [SshViewState].
extension SshViewStatePatterns on SshViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SshViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SshViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SshViewState value)  $default,){
final _that = this;
switch (_that) {
case _SshViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SshViewState value)?  $default,){
final _that = this;
switch (_that) {
case _SshViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RemoteState source,  Map<String, SshRowAction> actions,  int latestIntent,  SettingsAction? reloadAction,  SshEditorKey? editor,  String? directoryAlias,  int? directoryDialogId,  String? passwordAlias,  int? passwordDialogId,  int? passwordScopeId,  String? deleteConfirmationAlias)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SshViewState() when $default != null:
return $default(_that.source,_that.actions,_that.latestIntent,_that.reloadAction,_that.editor,_that.directoryAlias,_that.directoryDialogId,_that.passwordAlias,_that.passwordDialogId,_that.passwordScopeId,_that.deleteConfirmationAlias);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RemoteState source,  Map<String, SshRowAction> actions,  int latestIntent,  SettingsAction? reloadAction,  SshEditorKey? editor,  String? directoryAlias,  int? directoryDialogId,  String? passwordAlias,  int? passwordDialogId,  int? passwordScopeId,  String? deleteConfirmationAlias)  $default,) {final _that = this;
switch (_that) {
case _SshViewState():
return $default(_that.source,_that.actions,_that.latestIntent,_that.reloadAction,_that.editor,_that.directoryAlias,_that.directoryDialogId,_that.passwordAlias,_that.passwordDialogId,_that.passwordScopeId,_that.deleteConfirmationAlias);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RemoteState source,  Map<String, SshRowAction> actions,  int latestIntent,  SettingsAction? reloadAction,  SshEditorKey? editor,  String? directoryAlias,  int? directoryDialogId,  String? passwordAlias,  int? passwordDialogId,  int? passwordScopeId,  String? deleteConfirmationAlias)?  $default,) {final _that = this;
switch (_that) {
case _SshViewState() when $default != null:
return $default(_that.source,_that.actions,_that.latestIntent,_that.reloadAction,_that.editor,_that.directoryAlias,_that.directoryDialogId,_that.passwordAlias,_that.passwordDialogId,_that.passwordScopeId,_that.deleteConfirmationAlias);case _:
  return null;

}
}

}

/// @nodoc


class _SshViewState implements SshViewState {
  const _SshViewState({required this.source,  Map<String, SshRowAction> actions = const {}, this.latestIntent = 0, this.reloadAction, this.editor, this.directoryAlias, this.directoryDialogId, this.passwordAlias, this.passwordDialogId, this.passwordScopeId, this.deleteConfirmationAlias}): _actions = actions;


@override final  RemoteState source;
 final  Map<String, SshRowAction> _actions;
@override@JsonKey() Map<String, SshRowAction> get actions {
  if (_actions is EqualUnmodifiableMapView) return _actions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_actions);
}

@override@JsonKey() final  int latestIntent;
@override final  SettingsAction? reloadAction;
@override final  SshEditorKey? editor;
@override final  String? directoryAlias;
@override final  int? directoryDialogId;
@override final  String? passwordAlias;
@override final  int? passwordDialogId;
@override final  int? passwordScopeId;
@override final  String? deleteConfirmationAlias;

/// Create a copy of SshViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SshViewStateCopyWith<_SshViewState> get copyWith => __$SshViewStateCopyWithImpl<_SshViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SshViewState&&(identical(other.source, source) || other.source == source)&&const DeepCollectionEquality().equals(other.actions, _actions)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&(identical(other.reloadAction, reloadAction) || other.reloadAction == reloadAction)&&(identical(other.editor, editor) || other.editor == editor)&&(identical(other.directoryAlias, directoryAlias) || other.directoryAlias == directoryAlias)&&(identical(other.directoryDialogId, directoryDialogId) || other.directoryDialogId == directoryDialogId)&&(identical(other.passwordAlias, passwordAlias) || other.passwordAlias == passwordAlias)&&(identical(other.passwordDialogId, passwordDialogId) || other.passwordDialogId == passwordDialogId)&&(identical(other.passwordScopeId, passwordScopeId) || other.passwordScopeId == passwordScopeId)&&(identical(other.deleteConfirmationAlias, deleteConfirmationAlias) || other.deleteConfirmationAlias == deleteConfirmationAlias));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,const DeepCollectionEquality().hash(_actions),latestIntent,reloadAction,editor,directoryAlias,directoryDialogId,passwordAlias,passwordDialogId,passwordScopeId,deleteConfirmationAlias);
}



}

/// @nodoc
abstract mixin class _$SshViewStateCopyWith<$Res> implements $SshViewStateCopyWith<$Res> {
  factory _$SshViewStateCopyWith(_SshViewState value, $Res Function(_SshViewState) _then) = __$SshViewStateCopyWithImpl;
@override @useResult
$Res call({
 RemoteState source, Map<String, SshRowAction> actions, int latestIntent, SettingsAction? reloadAction, SshEditorKey? editor, String? directoryAlias, int? directoryDialogId, String? passwordAlias, int? passwordDialogId, int? passwordScopeId, String? deleteConfirmationAlias
});


@override $RemoteStateCopyWith<$Res> get source;@override $SettingsActionCopyWith<$Res>? get reloadAction;@override $SshEditorKeyCopyWith<$Res>? get editor;

}
/// @nodoc
class __$SshViewStateCopyWithImpl<$Res>
    implements _$SshViewStateCopyWith<$Res> {
  __$SshViewStateCopyWithImpl(this._self, this._then);

  final _SshViewState _self;
  final $Res Function(_SshViewState) _then;

/// Create a copy of SshViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? actions = null,Object? latestIntent = null,Object? reloadAction = freezed,Object? editor = freezed,Object? directoryAlias = freezed,Object? directoryDialogId = freezed,Object? passwordAlias = freezed,Object? passwordDialogId = freezed,Object? passwordScopeId = freezed,Object? deleteConfirmationAlias = freezed,}) {
  return _then(_SshViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as RemoteState,actions: null == actions ? _self._actions : actions // ignore: cast_nullable_to_non_nullable
as Map<String, SshRowAction>,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,reloadAction: freezed == reloadAction ? _self.reloadAction : reloadAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,editor: freezed == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as SshEditorKey?,directoryAlias: freezed == directoryAlias ? _self.directoryAlias : directoryAlias // ignore: cast_nullable_to_non_nullable
as String?,directoryDialogId: freezed == directoryDialogId ? _self.directoryDialogId : directoryDialogId // ignore: cast_nullable_to_non_nullable
as int?,passwordAlias: freezed == passwordAlias ? _self.passwordAlias : passwordAlias // ignore: cast_nullable_to_non_nullable
as String?,passwordDialogId: freezed == passwordDialogId ? _self.passwordDialogId : passwordDialogId // ignore: cast_nullable_to_non_nullable
as int?,passwordScopeId: freezed == passwordScopeId ? _self.passwordScopeId : passwordScopeId // ignore: cast_nullable_to_non_nullable
as int?,deleteConfirmationAlias: freezed == deleteConfirmationAlias ? _self.deleteConfirmationAlias : deleteConfirmationAlias // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of SshViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RemoteStateCopyWith<$Res> get source {

  return $RemoteStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of SshViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get reloadAction {
    if (_self.reloadAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.reloadAction!, (value) {
    return _then(_self.copyWith(reloadAction: value));
  });
}/// Create a copy of SshViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SshEditorKeyCopyWith<$Res>? get editor {
    if (_self.editor == null) {
    return null;
  }

  return $SshEditorKeyCopyWith<$Res>(_self.editor!, (value) {
    return _then(_self.copyWith(editor: value));
  });
}
}

// dart format on
