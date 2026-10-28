// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mode_workspace_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModeDetailSelection {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeDetailSelection);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModeDetailSelection()';
}


}

/// @nodoc
class $ModeDetailSelectionCopyWith<$Res>  {
$ModeDetailSelectionCopyWith(ModeDetailSelection _, $Res Function(ModeDetailSelection) __);
}


/// Adds pattern-matching-related methods to [ModeDetailSelection].
extension ModeDetailSelectionPatterns on ModeDetailSelection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ModeStageSelection value)?  stage,TResult Function( ModeTransitionSelection value)?  transition,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ModeStageSelection() when stage != null:
return stage(_that);case ModeTransitionSelection() when transition != null:
return transition(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ModeStageSelection value)  stage,required TResult Function( ModeTransitionSelection value)  transition,}){
final _that = this;
switch (_that) {
case ModeStageSelection():
return stage(_that);case ModeTransitionSelection():
return transition(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ModeStageSelection value)?  stage,TResult? Function( ModeTransitionSelection value)?  transition,}){
final _that = this;
switch (_that) {
case ModeStageSelection() when stage != null:
return stage(_that);case ModeTransitionSelection() when transition != null:
return transition(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String stateId)?  stage,TResult Function( String sourceStateId,  String targetStateId)?  transition,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ModeStageSelection() when stage != null:
return stage(_that.stateId);case ModeTransitionSelection() when transition != null:
return transition(_that.sourceStateId,_that.targetStateId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String stateId)  stage,required TResult Function( String sourceStateId,  String targetStateId)  transition,}) {final _that = this;
switch (_that) {
case ModeStageSelection():
return stage(_that.stateId);case ModeTransitionSelection():
return transition(_that.sourceStateId,_that.targetStateId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String stateId)?  stage,TResult? Function( String sourceStateId,  String targetStateId)?  transition,}) {final _that = this;
switch (_that) {
case ModeStageSelection() when stage != null:
return stage(_that.stateId);case ModeTransitionSelection() when transition != null:
return transition(_that.sourceStateId,_that.targetStateId);case _:
  return null;

}
}

}

/// @nodoc


class ModeStageSelection implements ModeDetailSelection {
  const ModeStageSelection(this.stateId);


 final  String stateId;

/// Create a copy of ModeDetailSelection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeStageSelectionCopyWith<ModeStageSelection> get copyWith => _$ModeStageSelectionCopyWithImpl<ModeStageSelection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeStageSelection&&(identical(other.stateId, stateId) || other.stateId == stateId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stateId);
}

@override
String toString() {
    return 'ModeDetailSelection.stage(stateId: $stateId)';
}


}

/// @nodoc
abstract mixin class $ModeStageSelectionCopyWith<$Res> implements $ModeDetailSelectionCopyWith<$Res> {
  factory $ModeStageSelectionCopyWith(ModeStageSelection value, $Res Function(ModeStageSelection) _then) = _$ModeStageSelectionCopyWithImpl;
@useResult
$Res call({
 String stateId
});




}
/// @nodoc
class _$ModeStageSelectionCopyWithImpl<$Res>
    implements $ModeStageSelectionCopyWith<$Res> {
  _$ModeStageSelectionCopyWithImpl(this._self, this._then);

  final ModeStageSelection _self;
  final $Res Function(ModeStageSelection) _then;

/// Create a copy of ModeDetailSelection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? stateId = null,}) {
  return _then(ModeStageSelection(
null == stateId ? _self.stateId : stateId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ModeTransitionSelection implements ModeDetailSelection {
  const ModeTransitionSelection({required this.sourceStateId, required this.targetStateId});


 final  String sourceStateId;
 final  String targetStateId;

/// Create a copy of ModeDetailSelection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeTransitionSelectionCopyWith<ModeTransitionSelection> get copyWith => _$ModeTransitionSelectionCopyWithImpl<ModeTransitionSelection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeTransitionSelection&&(identical(other.sourceStateId, sourceStateId) || other.sourceStateId == sourceStateId)&&(identical(other.targetStateId, targetStateId) || other.targetStateId == targetStateId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sourceStateId,targetStateId);
}

@override
String toString() {
    return 'ModeDetailSelection.transition(sourceStateId: $sourceStateId, targetStateId: $targetStateId)';
}


}

/// @nodoc
abstract mixin class $ModeTransitionSelectionCopyWith<$Res> implements $ModeDetailSelectionCopyWith<$Res> {
  factory $ModeTransitionSelectionCopyWith(ModeTransitionSelection value, $Res Function(ModeTransitionSelection) _then) = _$ModeTransitionSelectionCopyWithImpl;
@useResult
$Res call({
 String sourceStateId, String targetStateId
});




}
/// @nodoc
class _$ModeTransitionSelectionCopyWithImpl<$Res>
    implements $ModeTransitionSelectionCopyWith<$Res> {
  _$ModeTransitionSelectionCopyWithImpl(this._self, this._then);

  final ModeTransitionSelection _self;
  final $Res Function(ModeTransitionSelection) _then;

/// Create a copy of ModeDetailSelection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sourceStateId = null,Object? targetStateId = null,}) {
  return _then(ModeTransitionSelection(
sourceStateId: null == sourceStateId ? _self.sourceStateId : sourceStateId // ignore: cast_nullable_to_non_nullable
as String,targetStateId: null == targetStateId ? _self.targetStateId : targetStateId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ModeWorkspaceViewState {

 ModeWorkspaceSection get section; ModeDetailSelection? get selection; ModeWorkflowFocus get focus; bool get validationRequested; String get previewReason;
/// Create a copy of ModeWorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeWorkspaceViewStateCopyWith<ModeWorkspaceViewState> get copyWith => _$ModeWorkspaceViewStateCopyWithImpl<ModeWorkspaceViewState>(this as ModeWorkspaceViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeWorkspaceViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeWorkspaceViewState&&(identical(other.section, _this.section) || other.section == _this.section)&&(identical(other.selection, _this.selection) || other.selection == _this.selection)&&(identical(other.focus, _this.focus) || other.focus == _this.focus)&&(identical(other.validationRequested, _this.validationRequested) || other.validationRequested == _this.validationRequested)&&(identical(other.previewReason, _this.previewReason) || other.previewReason == _this.previewReason));
}


@override
int get hashCode {
  final _this = this as ModeWorkspaceViewState;
  return Object.hash(runtimeType,_this.section,_this.selection,_this.focus,_this.validationRequested,_this.previewReason);
}

@override
String toString() {
  final _this = this as ModeWorkspaceViewState;
  return 'ModeWorkspaceViewState(section: ${_this.section}, selection: ${_this.selection}, focus: ${_this.focus}, validationRequested: ${_this.validationRequested}, previewReason: ${_this.previewReason})';
}


}

/// @nodoc
abstract mixin class $ModeWorkspaceViewStateCopyWith<$Res>  {
  factory $ModeWorkspaceViewStateCopyWith(ModeWorkspaceViewState value, $Res Function(ModeWorkspaceViewState) _then) = _$ModeWorkspaceViewStateCopyWithImpl;
@useResult
$Res call({
 ModeWorkspaceSection section, ModeDetailSelection? selection, ModeWorkflowFocus focus, bool validationRequested, String previewReason
});


$ModeDetailSelectionCopyWith<$Res>? get selection;

}
/// @nodoc
class _$ModeWorkspaceViewStateCopyWithImpl<$Res>
    implements $ModeWorkspaceViewStateCopyWith<$Res> {
  _$ModeWorkspaceViewStateCopyWithImpl(this._self, this._then);

  final ModeWorkspaceViewState _self;
  final $Res Function(ModeWorkspaceViewState) _then;

/// Create a copy of ModeWorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? section = null,Object? selection = freezed,Object? focus = null,Object? validationRequested = null,Object? previewReason = null,}) {
  return _then(ModeWorkspaceViewState(
section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as ModeWorkspaceSection,selection: freezed == selection ? _self.selection : selection // ignore: cast_nullable_to_non_nullable
as ModeDetailSelection?,focus: null == focus ? _self.focus : focus // ignore: cast_nullable_to_non_nullable
as ModeWorkflowFocus,validationRequested: null == validationRequested ? _self.validationRequested : validationRequested // ignore: cast_nullable_to_non_nullable
as bool,previewReason: null == previewReason ? _self.previewReason : previewReason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of ModeWorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDetailSelectionCopyWith<$Res>? get selection {
    if (_self.selection == null) {
    return null;
  }

  return $ModeDetailSelectionCopyWith<$Res>(_self.selection!, (value) {
    return _then(_self.copyWith(selection: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeWorkspaceViewState].
extension ModeWorkspaceViewStatePatterns on ModeWorkspaceViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeWorkspaceViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeWorkspaceViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeWorkspaceViewState value)  $default,){
final _that = this;
switch (_that) {
case _ModeWorkspaceViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeWorkspaceViewState value)?  $default,){
final _that = this;
switch (_that) {
case _ModeWorkspaceViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModeWorkspaceSection section,  ModeDetailSelection? selection,  ModeWorkflowFocus focus,  bool validationRequested,  String previewReason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeWorkspaceViewState() when $default != null:
return $default(_that.section,_that.selection,_that.focus,_that.validationRequested,_that.previewReason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModeWorkspaceSection section,  ModeDetailSelection? selection,  ModeWorkflowFocus focus,  bool validationRequested,  String previewReason)  $default,) {final _that = this;
switch (_that) {
case _ModeWorkspaceViewState():
return $default(_that.section,_that.selection,_that.focus,_that.validationRequested,_that.previewReason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModeWorkspaceSection section,  ModeDetailSelection? selection,  ModeWorkflowFocus focus,  bool validationRequested,  String previewReason)?  $default,) {final _that = this;
switch (_that) {
case _ModeWorkspaceViewState() when $default != null:
return $default(_that.section,_that.selection,_that.focus,_that.validationRequested,_that.previewReason);case _:
  return null;

}
}

}

/// @nodoc


class _ModeWorkspaceViewState implements ModeWorkspaceViewState {
  const _ModeWorkspaceViewState({this.section = ModeWorkspaceSection.flow, this.selection, this.focus = ModeWorkflowFocus.all, this.validationRequested = false, this.previewReason = ''});


@override@JsonKey() final  ModeWorkspaceSection section;
@override final  ModeDetailSelection? selection;
@override@JsonKey() final  ModeWorkflowFocus focus;
@override@JsonKey() final  bool validationRequested;
@override@JsonKey() final  String previewReason;

/// Create a copy of ModeWorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeWorkspaceViewStateCopyWith<_ModeWorkspaceViewState> get copyWith => __$ModeWorkspaceViewStateCopyWithImpl<_ModeWorkspaceViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeWorkspaceViewState&&(identical(other.section, section) || other.section == section)&&(identical(other.selection, selection) || other.selection == selection)&&(identical(other.focus, focus) || other.focus == focus)&&(identical(other.validationRequested, validationRequested) || other.validationRequested == validationRequested)&&(identical(other.previewReason, previewReason) || other.previewReason == previewReason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,section,selection,focus,validationRequested,previewReason);
}

@override
String toString() {
    return 'ModeWorkspaceViewState(section: $section, selection: $selection, focus: $focus, validationRequested: $validationRequested, previewReason: $previewReason)';
}


}

/// @nodoc
abstract mixin class _$ModeWorkspaceViewStateCopyWith<$Res> implements $ModeWorkspaceViewStateCopyWith<$Res> {
  factory _$ModeWorkspaceViewStateCopyWith(_ModeWorkspaceViewState value, $Res Function(_ModeWorkspaceViewState) _then) = __$ModeWorkspaceViewStateCopyWithImpl;
@override @useResult
$Res call({
 ModeWorkspaceSection section, ModeDetailSelection? selection, ModeWorkflowFocus focus, bool validationRequested, String previewReason
});


@override $ModeDetailSelectionCopyWith<$Res>? get selection;

}
/// @nodoc
class __$ModeWorkspaceViewStateCopyWithImpl<$Res>
    implements _$ModeWorkspaceViewStateCopyWith<$Res> {
  __$ModeWorkspaceViewStateCopyWithImpl(this._self, this._then);

  final _ModeWorkspaceViewState _self;
  final $Res Function(_ModeWorkspaceViewState) _then;

/// Create a copy of ModeWorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? section = null,Object? selection = freezed,Object? focus = null,Object? validationRequested = null,Object? previewReason = null,}) {
  return _then(_ModeWorkspaceViewState(
section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as ModeWorkspaceSection,selection: freezed == selection ? _self.selection : selection // ignore: cast_nullable_to_non_nullable
as ModeDetailSelection?,focus: null == focus ? _self.focus : focus // ignore: cast_nullable_to_non_nullable
as ModeWorkflowFocus,validationRequested: null == validationRequested ? _self.validationRequested : validationRequested // ignore: cast_nullable_to_non_nullable
as bool,previewReason: null == previewReason ? _self.previewReason : previewReason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of ModeWorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDetailSelectionCopyWith<$Res>? get selection {
    if (_self.selection == null) {
    return null;
  }

  return $ModeDetailSelectionCopyWith<$Res>(_self.selection!, (value) {
    return _then(_self.copyWith(selection: value));
  });
}
}

// dart format on
