// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_account_save_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AcpAccountSaveViewState {

 String get accountId; int get latestIntent; SettingsAction? get saveAction; SettingsAction? get checkAction; StudioFailure? get saveError; StudioFailure? get checkError;/// 配置写入已成功结算（canonical 事实成立）。
 bool get saved;/// 保存后解析到的连接代次；0 表示尚未解析到。
 int get connectionRevision;
/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountSaveViewStateCopyWith<AcpAccountSaveViewState> get copyWith => _$AcpAccountSaveViewStateCopyWithImpl<AcpAccountSaveViewState>(this as AcpAccountSaveViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAccountSaveViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountSaveViewState&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&(identical(other.saveAction, _this.saveAction) || other.saveAction == _this.saveAction)&&(identical(other.checkAction, _this.checkAction) || other.checkAction == _this.checkAction)&&(identical(other.saveError, _this.saveError) || other.saveError == _this.saveError)&&(identical(other.checkError, _this.checkError) || other.checkError == _this.checkError)&&(identical(other.saved, _this.saved) || other.saved == _this.saved)&&(identical(other.connectionRevision, _this.connectionRevision) || other.connectionRevision == _this.connectionRevision));
}


@override
int get hashCode {
  final _this = this as AcpAccountSaveViewState;
  return Object.hash(runtimeType,_this.accountId,_this.latestIntent,_this.saveAction,_this.checkAction,_this.saveError,_this.checkError,_this.saved,_this.connectionRevision);
}



}

/// @nodoc
abstract mixin class $AcpAccountSaveViewStateCopyWith<$Res>  {
  factory $AcpAccountSaveViewStateCopyWith(AcpAccountSaveViewState value, $Res Function(AcpAccountSaveViewState) _then) = _$AcpAccountSaveViewStateCopyWithImpl;
@useResult
$Res call({
 String accountId, int latestIntent, SettingsAction? saveAction, SettingsAction? checkAction, StudioFailure? saveError, StudioFailure? checkError, bool saved, int connectionRevision
});


$SettingsActionCopyWith<$Res>? get saveAction;$SettingsActionCopyWith<$Res>? get checkAction;$StudioFailureCopyWith<$Res>? get saveError;$StudioFailureCopyWith<$Res>? get checkError;

}
/// @nodoc
class _$AcpAccountSaveViewStateCopyWithImpl<$Res>
    implements $AcpAccountSaveViewStateCopyWith<$Res> {
  _$AcpAccountSaveViewStateCopyWithImpl(this._self, this._then);

  final AcpAccountSaveViewState _self;
  final $Res Function(AcpAccountSaveViewState) _then;

/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? latestIntent = null,Object? saveAction = freezed,Object? checkAction = freezed,Object? saveError = freezed,Object? checkError = freezed,Object? saved = null,Object? connectionRevision = null,}) {
  return _then(AcpAccountSaveViewState(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,saveAction: freezed == saveAction ? _self.saveAction : saveAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,checkAction: freezed == checkAction ? _self.checkAction : checkAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,saveError: freezed == saveError ? _self.saveError : saveError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,checkError: freezed == checkError ? _self.checkError : checkError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,connectionRevision: null == connectionRevision ? _self.connectionRevision : connectionRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get saveAction {
    if (_self.saveAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.saveAction!, (value) {
    return _then(_self.copyWith(saveAction: value));
  });
}/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get checkAction {
    if (_self.checkAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.checkAction!, (value) {
    return _then(_self.copyWith(checkAction: value));
  });
}/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get saveError {
    if (_self.saveError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.saveError!, (value) {
    return _then(_self.copyWith(saveError: value));
  });
}/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get checkError {
    if (_self.checkError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.checkError!, (value) {
    return _then(_self.copyWith(checkError: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAccountSaveViewState].
extension AcpAccountSaveViewStatePatterns on AcpAccountSaveViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAccountSaveViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAccountSaveViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAccountSaveViewState value)  $default,){
final _that = this;
switch (_that) {
case _AcpAccountSaveViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAccountSaveViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAccountSaveViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  int latestIntent,  SettingsAction? saveAction,  SettingsAction? checkAction,  StudioFailure? saveError,  StudioFailure? checkError,  bool saved,  int connectionRevision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAccountSaveViewState() when $default != null:
return $default(_that.accountId,_that.latestIntent,_that.saveAction,_that.checkAction,_that.saveError,_that.checkError,_that.saved,_that.connectionRevision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  int latestIntent,  SettingsAction? saveAction,  SettingsAction? checkAction,  StudioFailure? saveError,  StudioFailure? checkError,  bool saved,  int connectionRevision)  $default,) {final _that = this;
switch (_that) {
case _AcpAccountSaveViewState():
return $default(_that.accountId,_that.latestIntent,_that.saveAction,_that.checkAction,_that.saveError,_that.checkError,_that.saved,_that.connectionRevision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  int latestIntent,  SettingsAction? saveAction,  SettingsAction? checkAction,  StudioFailure? saveError,  StudioFailure? checkError,  bool saved,  int connectionRevision)?  $default,) {final _that = this;
switch (_that) {
case _AcpAccountSaveViewState() when $default != null:
return $default(_that.accountId,_that.latestIntent,_that.saveAction,_that.checkAction,_that.saveError,_that.checkError,_that.saved,_that.connectionRevision);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAccountSaveViewState extends AcpAccountSaveViewState {
  const _AcpAccountSaveViewState({required this.accountId, this.latestIntent = 0, this.saveAction, this.checkAction, this.saveError, this.checkError, this.saved = false, this.connectionRevision = 0}): super._();


@override final  String accountId;
@override@JsonKey() final  int latestIntent;
@override final  SettingsAction? saveAction;
@override final  SettingsAction? checkAction;
@override final  StudioFailure? saveError;
@override final  StudioFailure? checkError;
/// 配置写入已成功结算（canonical 事实成立）。
@override@JsonKey() final  bool saved;
/// 保存后解析到的连接代次；0 表示尚未解析到。
@override@JsonKey() final  int connectionRevision;

/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAccountSaveViewStateCopyWith<_AcpAccountSaveViewState> get copyWith => __$AcpAccountSaveViewStateCopyWithImpl<_AcpAccountSaveViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAccountSaveViewState&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&(identical(other.saveAction, saveAction) || other.saveAction == saveAction)&&(identical(other.checkAction, checkAction) || other.checkAction == checkAction)&&(identical(other.saveError, saveError) || other.saveError == saveError)&&(identical(other.checkError, checkError) || other.checkError == checkError)&&(identical(other.saved, saved) || other.saved == saved)&&(identical(other.connectionRevision, connectionRevision) || other.connectionRevision == connectionRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,latestIntent,saveAction,checkAction,saveError,checkError,saved,connectionRevision);
}



}

/// @nodoc
abstract mixin class _$AcpAccountSaveViewStateCopyWith<$Res> implements $AcpAccountSaveViewStateCopyWith<$Res> {
  factory _$AcpAccountSaveViewStateCopyWith(_AcpAccountSaveViewState value, $Res Function(_AcpAccountSaveViewState) _then) = __$AcpAccountSaveViewStateCopyWithImpl;
@override @useResult
$Res call({
 String accountId, int latestIntent, SettingsAction? saveAction, SettingsAction? checkAction, StudioFailure? saveError, StudioFailure? checkError, bool saved, int connectionRevision
});


@override $SettingsActionCopyWith<$Res>? get saveAction;@override $SettingsActionCopyWith<$Res>? get checkAction;@override $StudioFailureCopyWith<$Res>? get saveError;@override $StudioFailureCopyWith<$Res>? get checkError;

}
/// @nodoc
class __$AcpAccountSaveViewStateCopyWithImpl<$Res>
    implements _$AcpAccountSaveViewStateCopyWith<$Res> {
  __$AcpAccountSaveViewStateCopyWithImpl(this._self, this._then);

  final _AcpAccountSaveViewState _self;
  final $Res Function(_AcpAccountSaveViewState) _then;

/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? latestIntent = null,Object? saveAction = freezed,Object? checkAction = freezed,Object? saveError = freezed,Object? checkError = freezed,Object? saved = null,Object? connectionRevision = null,}) {
  return _then(_AcpAccountSaveViewState(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,saveAction: freezed == saveAction ? _self.saveAction : saveAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,checkAction: freezed == checkAction ? _self.checkAction : checkAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,saveError: freezed == saveError ? _self.saveError : saveError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,checkError: freezed == checkError ? _self.checkError : checkError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,connectionRevision: null == connectionRevision ? _self.connectionRevision : connectionRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get saveAction {
    if (_self.saveAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.saveAction!, (value) {
    return _then(_self.copyWith(saveAction: value));
  });
}/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get checkAction {
    if (_self.checkAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.checkAction!, (value) {
    return _then(_self.copyWith(checkAction: value));
  });
}/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get saveError {
    if (_self.saveError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.saveError!, (value) {
    return _then(_self.copyWith(saveError: value));
  });
}/// Create a copy of AcpAccountSaveViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get checkError {
    if (_self.checkError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.checkError!, (value) {
    return _then(_self.copyWith(checkError: value));
  });
}
}

// dart format on
