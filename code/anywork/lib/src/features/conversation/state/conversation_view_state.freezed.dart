// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConversationViewState {

 String get threadId; ThreadMetadataState? get metadata; ThreadExecutionState? get execution; ThreadConfigurationState? get configuration; ComposerBlocker? get workspaceBlocker; bool get acceptsUserInput; InteractionIndexReadState? get interactions; List<InteractionEditorKey> get visibleEditors; Set<InteractionEditorKey> get currentEditors; bool get indexLoading; StudioFailure? get indexError; bool get stopSourceCurrent; ConversationStopState? get stop; ConversationContinuationState? get continuation;
/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationViewStateCopyWith<ConversationViewState> get copyWith => _$ConversationViewStateCopyWithImpl<ConversationViewState>(this as ConversationViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConversationViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationViewState&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.metadata, _this.metadata) || other.metadata == _this.metadata)&&(identical(other.execution, _this.execution) || other.execution == _this.execution)&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.workspaceBlocker, _this.workspaceBlocker) || other.workspaceBlocker == _this.workspaceBlocker)&&(identical(other.acceptsUserInput, _this.acceptsUserInput) || other.acceptsUserInput == _this.acceptsUserInput)&&(identical(other.interactions, _this.interactions) || other.interactions == _this.interactions)&&const DeepCollectionEquality().equals(other.visibleEditors, _this.visibleEditors)&&const DeepCollectionEquality().equals(other.currentEditors, _this.currentEditors)&&(identical(other.indexLoading, _this.indexLoading) || other.indexLoading == _this.indexLoading)&&(identical(other.indexError, _this.indexError) || other.indexError == _this.indexError)&&(identical(other.stopSourceCurrent, _this.stopSourceCurrent) || other.stopSourceCurrent == _this.stopSourceCurrent)&&(identical(other.stop, _this.stop) || other.stop == _this.stop)&&(identical(other.continuation, _this.continuation) || other.continuation == _this.continuation));
}


@override
int get hashCode {
  final _this = this as ConversationViewState;
  return Object.hash(runtimeType,_this.threadId,_this.metadata,_this.execution,_this.configuration,_this.workspaceBlocker,_this.acceptsUserInput,_this.interactions,const DeepCollectionEquality().hash(_this.visibleEditors),const DeepCollectionEquality().hash(_this.currentEditors),_this.indexLoading,_this.indexError,_this.stopSourceCurrent,_this.stop,_this.continuation);
}



}

/// @nodoc
abstract mixin class $ConversationViewStateCopyWith<$Res>  {
  factory $ConversationViewStateCopyWith(ConversationViewState value, $Res Function(ConversationViewState) _then) = _$ConversationViewStateCopyWithImpl;
@useResult
$Res call({
 String threadId, ThreadMetadataState? metadata, ThreadExecutionState? execution, ThreadConfigurationState? configuration, ComposerBlocker? workspaceBlocker, bool acceptsUserInput, InteractionIndexReadState? interactions, List<InteractionEditorKey> visibleEditors, Set<InteractionEditorKey> currentEditors, bool indexLoading, StudioFailure? indexError, bool stopSourceCurrent, ConversationStopState? stop, ConversationContinuationState? continuation
});


$ThreadMetadataStateCopyWith<$Res>? get metadata;$ThreadExecutionStateCopyWith<$Res>? get execution;$ThreadConfigurationStateCopyWith<$Res>? get configuration;$ComposerBlockerCopyWith<$Res>? get workspaceBlocker;$InteractionIndexReadStateCopyWith<$Res>? get interactions;$StudioFailureCopyWith<$Res>? get indexError;$ConversationStopStateCopyWith<$Res>? get stop;$ConversationContinuationStateCopyWith<$Res>? get continuation;

}
/// @nodoc
class _$ConversationViewStateCopyWithImpl<$Res>
    implements $ConversationViewStateCopyWith<$Res> {
  _$ConversationViewStateCopyWithImpl(this._self, this._then);

  final ConversationViewState _self;
  final $Res Function(ConversationViewState) _then;

/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? metadata = freezed,Object? execution = freezed,Object? configuration = freezed,Object? workspaceBlocker = freezed,Object? acceptsUserInput = null,Object? interactions = freezed,Object? visibleEditors = null,Object? currentEditors = null,Object? indexLoading = null,Object? indexError = freezed,Object? stopSourceCurrent = null,Object? stop = freezed,Object? continuation = freezed,}) {
  return _then(ConversationViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as ThreadMetadataState?,execution: freezed == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as ThreadExecutionState?,configuration: freezed == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationState?,workspaceBlocker: freezed == workspaceBlocker ? _self.workspaceBlocker : workspaceBlocker // ignore: cast_nullable_to_non_nullable
as ComposerBlocker?,acceptsUserInput: null == acceptsUserInput ? _self.acceptsUserInput : acceptsUserInput // ignore: cast_nullable_to_non_nullable
as bool,interactions: freezed == interactions ? _self.interactions : interactions // ignore: cast_nullable_to_non_nullable
as InteractionIndexReadState?,visibleEditors: null == visibleEditors ? _self.visibleEditors : visibleEditors // ignore: cast_nullable_to_non_nullable
as List<InteractionEditorKey>,currentEditors: null == currentEditors ? _self.currentEditors : currentEditors // ignore: cast_nullable_to_non_nullable
as Set<InteractionEditorKey>,indexLoading: null == indexLoading ? _self.indexLoading : indexLoading // ignore: cast_nullable_to_non_nullable
as bool,indexError: freezed == indexError ? _self.indexError : indexError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,stopSourceCurrent: null == stopSourceCurrent ? _self.stopSourceCurrent : stopSourceCurrent // ignore: cast_nullable_to_non_nullable
as bool,stop: freezed == stop ? _self.stop : stop // ignore: cast_nullable_to_non_nullable
as ConversationStopState?,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as ConversationContinuationState?,
  ));
}
/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetadataStateCopyWith<$Res>? get metadata {
    if (_self.metadata == null) {
    return null;
  }

  return $ThreadMetadataStateCopyWith<$Res>(_self.metadata!, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadExecutionStateCopyWith<$Res>? get execution {
    if (_self.execution == null) {
    return null;
  }

  return $ThreadExecutionStateCopyWith<$Res>(_self.execution!, (value) {
    return _then(_self.copyWith(execution: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationStateCopyWith<$Res>? get configuration {
    if (_self.configuration == null) {
    return null;
  }

  return $ThreadConfigurationStateCopyWith<$Res>(_self.configuration!, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ComposerBlockerCopyWith<$Res>? get workspaceBlocker {
    if (_self.workspaceBlocker == null) {
    return null;
  }

  return $ComposerBlockerCopyWith<$Res>(_self.workspaceBlocker!, (value) {
    return _then(_self.copyWith(workspaceBlocker: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexReadStateCopyWith<$Res>? get interactions {
    if (_self.interactions == null) {
    return null;
  }

  return $InteractionIndexReadStateCopyWith<$Res>(_self.interactions!, (value) {
    return _then(_self.copyWith(interactions: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get indexError {
    if (_self.indexError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.indexError!, (value) {
    return _then(_self.copyWith(indexError: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationStopStateCopyWith<$Res>? get stop {
    if (_self.stop == null) {
    return null;
  }

  return $ConversationStopStateCopyWith<$Res>(_self.stop!, (value) {
    return _then(_self.copyWith(stop: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationContinuationStateCopyWith<$Res>? get continuation {
    if (_self.continuation == null) {
    return null;
  }

  return $ConversationContinuationStateCopyWith<$Res>(_self.continuation!, (value) {
    return _then(_self.copyWith(continuation: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConversationViewState].
extension ConversationViewStatePatterns on ConversationViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationViewState value)  $default,){
final _that = this;
switch (_that) {
case _ConversationViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationViewState value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  ThreadMetadataState? metadata,  ThreadExecutionState? execution,  ThreadConfigurationState? configuration,  ComposerBlocker? workspaceBlocker,  bool acceptsUserInput,  InteractionIndexReadState? interactions,  List<InteractionEditorKey> visibleEditors,  Set<InteractionEditorKey> currentEditors,  bool indexLoading,  StudioFailure? indexError,  bool stopSourceCurrent,  ConversationStopState? stop,  ConversationContinuationState? continuation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationViewState() when $default != null:
return $default(_that.threadId,_that.metadata,_that.execution,_that.configuration,_that.workspaceBlocker,_that.acceptsUserInput,_that.interactions,_that.visibleEditors,_that.currentEditors,_that.indexLoading,_that.indexError,_that.stopSourceCurrent,_that.stop,_that.continuation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  ThreadMetadataState? metadata,  ThreadExecutionState? execution,  ThreadConfigurationState? configuration,  ComposerBlocker? workspaceBlocker,  bool acceptsUserInput,  InteractionIndexReadState? interactions,  List<InteractionEditorKey> visibleEditors,  Set<InteractionEditorKey> currentEditors,  bool indexLoading,  StudioFailure? indexError,  bool stopSourceCurrent,  ConversationStopState? stop,  ConversationContinuationState? continuation)  $default,) {final _that = this;
switch (_that) {
case _ConversationViewState():
return $default(_that.threadId,_that.metadata,_that.execution,_that.configuration,_that.workspaceBlocker,_that.acceptsUserInput,_that.interactions,_that.visibleEditors,_that.currentEditors,_that.indexLoading,_that.indexError,_that.stopSourceCurrent,_that.stop,_that.continuation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  ThreadMetadataState? metadata,  ThreadExecutionState? execution,  ThreadConfigurationState? configuration,  ComposerBlocker? workspaceBlocker,  bool acceptsUserInput,  InteractionIndexReadState? interactions,  List<InteractionEditorKey> visibleEditors,  Set<InteractionEditorKey> currentEditors,  bool indexLoading,  StudioFailure? indexError,  bool stopSourceCurrent,  ConversationStopState? stop,  ConversationContinuationState? continuation)?  $default,) {final _that = this;
switch (_that) {
case _ConversationViewState() when $default != null:
return $default(_that.threadId,_that.metadata,_that.execution,_that.configuration,_that.workspaceBlocker,_that.acceptsUserInput,_that.interactions,_that.visibleEditors,_that.currentEditors,_that.indexLoading,_that.indexError,_that.stopSourceCurrent,_that.stop,_that.continuation);case _:
  return null;

}
}

}

/// @nodoc


class _ConversationViewState extends ConversationViewState {
  const _ConversationViewState({required this.threadId, this.metadata, this.execution, this.configuration, this.workspaceBlocker, this.acceptsUserInput = false, this.interactions,  List<InteractionEditorKey> visibleEditors = const [],  Set<InteractionEditorKey> currentEditors = const {}, this.indexLoading = false, this.indexError, this.stopSourceCurrent = false, this.stop, this.continuation}): _visibleEditors = visibleEditors,_currentEditors = currentEditors,super._();


@override final  String threadId;
@override final  ThreadMetadataState? metadata;
@override final  ThreadExecutionState? execution;
@override final  ThreadConfigurationState? configuration;
@override final  ComposerBlocker? workspaceBlocker;
@override@JsonKey() final  bool acceptsUserInput;
@override final  InteractionIndexReadState? interactions;
 final  List<InteractionEditorKey> _visibleEditors;
@override@JsonKey() List<InteractionEditorKey> get visibleEditors {
  if (_visibleEditors is EqualUnmodifiableListView) return _visibleEditors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_visibleEditors);
}

 final  Set<InteractionEditorKey> _currentEditors;
@override@JsonKey() Set<InteractionEditorKey> get currentEditors {
  if (_currentEditors is EqualUnmodifiableSetView) return _currentEditors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_currentEditors);
}

@override@JsonKey() final  bool indexLoading;
@override final  StudioFailure? indexError;
@override@JsonKey() final  bool stopSourceCurrent;
@override final  ConversationStopState? stop;
@override final  ConversationContinuationState? continuation;

/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationViewStateCopyWith<_ConversationViewState> get copyWith => __$ConversationViewStateCopyWithImpl<_ConversationViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationViewState&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&(identical(other.execution, execution) || other.execution == execution)&&(identical(other.configuration, configuration) || other.configuration == configuration)&&(identical(other.workspaceBlocker, workspaceBlocker) || other.workspaceBlocker == workspaceBlocker)&&(identical(other.acceptsUserInput, acceptsUserInput) || other.acceptsUserInput == acceptsUserInput)&&(identical(other.interactions, interactions) || other.interactions == interactions)&&const DeepCollectionEquality().equals(other.visibleEditors, _visibleEditors)&&const DeepCollectionEquality().equals(other.currentEditors, _currentEditors)&&(identical(other.indexLoading, indexLoading) || other.indexLoading == indexLoading)&&(identical(other.indexError, indexError) || other.indexError == indexError)&&(identical(other.stopSourceCurrent, stopSourceCurrent) || other.stopSourceCurrent == stopSourceCurrent)&&(identical(other.stop, stop) || other.stop == stop)&&(identical(other.continuation, continuation) || other.continuation == continuation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,metadata,execution,configuration,workspaceBlocker,acceptsUserInput,interactions,const DeepCollectionEquality().hash(_visibleEditors),const DeepCollectionEquality().hash(_currentEditors),indexLoading,indexError,stopSourceCurrent,stop,continuation);
}



}

/// @nodoc
abstract mixin class _$ConversationViewStateCopyWith<$Res> implements $ConversationViewStateCopyWith<$Res> {
  factory _$ConversationViewStateCopyWith(_ConversationViewState value, $Res Function(_ConversationViewState) _then) = __$ConversationViewStateCopyWithImpl;
@override @useResult
$Res call({
 String threadId, ThreadMetadataState? metadata, ThreadExecutionState? execution, ThreadConfigurationState? configuration, ComposerBlocker? workspaceBlocker, bool acceptsUserInput, InteractionIndexReadState? interactions, List<InteractionEditorKey> visibleEditors, Set<InteractionEditorKey> currentEditors, bool indexLoading, StudioFailure? indexError, bool stopSourceCurrent, ConversationStopState? stop, ConversationContinuationState? continuation
});


@override $ThreadMetadataStateCopyWith<$Res>? get metadata;@override $ThreadExecutionStateCopyWith<$Res>? get execution;@override $ThreadConfigurationStateCopyWith<$Res>? get configuration;@override $ComposerBlockerCopyWith<$Res>? get workspaceBlocker;@override $InteractionIndexReadStateCopyWith<$Res>? get interactions;@override $StudioFailureCopyWith<$Res>? get indexError;@override $ConversationStopStateCopyWith<$Res>? get stop;@override $ConversationContinuationStateCopyWith<$Res>? get continuation;

}
/// @nodoc
class __$ConversationViewStateCopyWithImpl<$Res>
    implements _$ConversationViewStateCopyWith<$Res> {
  __$ConversationViewStateCopyWithImpl(this._self, this._then);

  final _ConversationViewState _self;
  final $Res Function(_ConversationViewState) _then;

/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? metadata = freezed,Object? execution = freezed,Object? configuration = freezed,Object? workspaceBlocker = freezed,Object? acceptsUserInput = null,Object? interactions = freezed,Object? visibleEditors = null,Object? currentEditors = null,Object? indexLoading = null,Object? indexError = freezed,Object? stopSourceCurrent = null,Object? stop = freezed,Object? continuation = freezed,}) {
  return _then(_ConversationViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as ThreadMetadataState?,execution: freezed == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as ThreadExecutionState?,configuration: freezed == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationState?,workspaceBlocker: freezed == workspaceBlocker ? _self.workspaceBlocker : workspaceBlocker // ignore: cast_nullable_to_non_nullable
as ComposerBlocker?,acceptsUserInput: null == acceptsUserInput ? _self.acceptsUserInput : acceptsUserInput // ignore: cast_nullable_to_non_nullable
as bool,interactions: freezed == interactions ? _self.interactions : interactions // ignore: cast_nullable_to_non_nullable
as InteractionIndexReadState?,visibleEditors: null == visibleEditors ? _self._visibleEditors : visibleEditors // ignore: cast_nullable_to_non_nullable
as List<InteractionEditorKey>,currentEditors: null == currentEditors ? _self._currentEditors : currentEditors // ignore: cast_nullable_to_non_nullable
as Set<InteractionEditorKey>,indexLoading: null == indexLoading ? _self.indexLoading : indexLoading // ignore: cast_nullable_to_non_nullable
as bool,indexError: freezed == indexError ? _self.indexError : indexError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,stopSourceCurrent: null == stopSourceCurrent ? _self.stopSourceCurrent : stopSourceCurrent // ignore: cast_nullable_to_non_nullable
as bool,stop: freezed == stop ? _self.stop : stop // ignore: cast_nullable_to_non_nullable
as ConversationStopState?,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as ConversationContinuationState?,
  ));
}

/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetadataStateCopyWith<$Res>? get metadata {
    if (_self.metadata == null) {
    return null;
  }

  return $ThreadMetadataStateCopyWith<$Res>(_self.metadata!, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadExecutionStateCopyWith<$Res>? get execution {
    if (_self.execution == null) {
    return null;
  }

  return $ThreadExecutionStateCopyWith<$Res>(_self.execution!, (value) {
    return _then(_self.copyWith(execution: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationStateCopyWith<$Res>? get configuration {
    if (_self.configuration == null) {
    return null;
  }

  return $ThreadConfigurationStateCopyWith<$Res>(_self.configuration!, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ComposerBlockerCopyWith<$Res>? get workspaceBlocker {
    if (_self.workspaceBlocker == null) {
    return null;
  }

  return $ComposerBlockerCopyWith<$Res>(_self.workspaceBlocker!, (value) {
    return _then(_self.copyWith(workspaceBlocker: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexReadStateCopyWith<$Res>? get interactions {
    if (_self.interactions == null) {
    return null;
  }

  return $InteractionIndexReadStateCopyWith<$Res>(_self.interactions!, (value) {
    return _then(_self.copyWith(interactions: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get indexError {
    if (_self.indexError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.indexError!, (value) {
    return _then(_self.copyWith(indexError: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationStopStateCopyWith<$Res>? get stop {
    if (_self.stop == null) {
    return null;
  }

  return $ConversationStopStateCopyWith<$Res>(_self.stop!, (value) {
    return _then(_self.copyWith(stop: value));
  });
}/// Create a copy of ConversationViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationContinuationStateCopyWith<$Res>? get continuation {
    if (_self.continuation == null) {
    return null;
  }

  return $ConversationContinuationStateCopyWith<$Res>(_self.continuation!, (value) {
    return _then(_self.copyWith(continuation: value));
  });
}
}

/// @nodoc
mixin _$ConversationStopState {

 int get intent; ThreadFacetStamp? get origin; String? get executionId; OperationState? get operation; CommandResult<Unit>? get result; StudioFailure? get localError; StudioFailure? get observationError;
/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationStopStateCopyWith<ConversationStopState> get copyWith => _$ConversationStopStateCopyWithImpl<ConversationStopState>(this as ConversationStopState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConversationStopState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationStopState&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.executionId, _this.executionId) || other.executionId == _this.executionId)&&(identical(other.operation, _this.operation) || other.operation == _this.operation)&&(identical(other.result, _this.result) || other.result == _this.result)&&(identical(other.localError, _this.localError) || other.localError == _this.localError)&&(identical(other.observationError, _this.observationError) || other.observationError == _this.observationError));
}


@override
int get hashCode {
  final _this = this as ConversationStopState;
  return Object.hash(runtimeType,_this.intent,_this.origin,_this.executionId,_this.operation,_this.result,_this.localError,_this.observationError);
}



}

/// @nodoc
abstract mixin class $ConversationStopStateCopyWith<$Res>  {
  factory $ConversationStopStateCopyWith(ConversationStopState value, $Res Function(ConversationStopState) _then) = _$ConversationStopStateCopyWithImpl;
@useResult
$Res call({
 int intent, ThreadFacetStamp? origin, String? executionId, OperationState? operation, CommandResult<Unit>? result, StudioFailure? localError, StudioFailure? observationError
});


$ThreadFacetStampCopyWith<$Res>? get origin;$OperationStateCopyWith<$Res>? get operation;$CommandResultCopyWith<Unit, $Res>? get result;$StudioFailureCopyWith<$Res>? get localError;$StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class _$ConversationStopStateCopyWithImpl<$Res>
    implements $ConversationStopStateCopyWith<$Res> {
  _$ConversationStopStateCopyWithImpl(this._self, this._then);

  final ConversationStopState _self;
  final $Res Function(ConversationStopState) _then;

/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,Object? origin = freezed,Object? executionId = freezed,Object? operation = freezed,Object? result = freezed,Object? localError = freezed,Object? observationError = freezed,}) {
  return _then(ConversationStopState(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,origin: freezed == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,executionId: freezed == executionId ? _self.executionId : executionId // ignore: cast_nullable_to_non_nullable
as String?,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as CommandResult<Unit>?,localError: freezed == localError ? _self.localError : localError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get origin {
    if (_self.origin == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.origin!, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommandResultCopyWith<Unit, $Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $CommandResultCopyWith<Unit, $Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get localError {
    if (_self.localError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.localError!, (value) {
    return _then(_self.copyWith(localError: value));
  });
}/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get observationError {
    if (_self.observationError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.observationError!, (value) {
    return _then(_self.copyWith(observationError: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConversationStopState].
extension ConversationStopStatePatterns on ConversationStopState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationStopState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationStopState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationStopState value)  $default,){
final _that = this;
switch (_that) {
case _ConversationStopState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationStopState value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationStopState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int intent,  ThreadFacetStamp? origin,  String? executionId,  OperationState? operation,  CommandResult<Unit>? result,  StudioFailure? localError,  StudioFailure? observationError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationStopState() when $default != null:
return $default(_that.intent,_that.origin,_that.executionId,_that.operation,_that.result,_that.localError,_that.observationError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int intent,  ThreadFacetStamp? origin,  String? executionId,  OperationState? operation,  CommandResult<Unit>? result,  StudioFailure? localError,  StudioFailure? observationError)  $default,) {final _that = this;
switch (_that) {
case _ConversationStopState():
return $default(_that.intent,_that.origin,_that.executionId,_that.operation,_that.result,_that.localError,_that.observationError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int intent,  ThreadFacetStamp? origin,  String? executionId,  OperationState? operation,  CommandResult<Unit>? result,  StudioFailure? localError,  StudioFailure? observationError)?  $default,) {final _that = this;
switch (_that) {
case _ConversationStopState() when $default != null:
return $default(_that.intent,_that.origin,_that.executionId,_that.operation,_that.result,_that.localError,_that.observationError);case _:
  return null;

}
}

}

/// @nodoc


class _ConversationStopState extends ConversationStopState {
  const _ConversationStopState({required this.intent, this.origin, this.executionId, this.operation, this.result, this.localError, this.observationError}): super._();


@override final  int intent;
@override final  ThreadFacetStamp? origin;
@override final  String? executionId;
@override final  OperationState? operation;
@override final  CommandResult<Unit>? result;
@override final  StudioFailure? localError;
@override final  StudioFailure? observationError;

/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationStopStateCopyWith<_ConversationStopState> get copyWith => __$ConversationStopStateCopyWithImpl<_ConversationStopState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationStopState&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.executionId, executionId) || other.executionId == executionId)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.result, result) || other.result == result)&&(identical(other.localError, localError) || other.localError == localError)&&(identical(other.observationError, observationError) || other.observationError == observationError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,origin,executionId,operation,result,localError,observationError);
}



}

/// @nodoc
abstract mixin class _$ConversationStopStateCopyWith<$Res> implements $ConversationStopStateCopyWith<$Res> {
  factory _$ConversationStopStateCopyWith(_ConversationStopState value, $Res Function(_ConversationStopState) _then) = __$ConversationStopStateCopyWithImpl;
@override @useResult
$Res call({
 int intent, ThreadFacetStamp? origin, String? executionId, OperationState? operation, CommandResult<Unit>? result, StudioFailure? localError, StudioFailure? observationError
});


@override $ThreadFacetStampCopyWith<$Res>? get origin;@override $OperationStateCopyWith<$Res>? get operation;@override $CommandResultCopyWith<Unit, $Res>? get result;@override $StudioFailureCopyWith<$Res>? get localError;@override $StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class __$ConversationStopStateCopyWithImpl<$Res>
    implements _$ConversationStopStateCopyWith<$Res> {
  __$ConversationStopStateCopyWithImpl(this._self, this._then);

  final _ConversationStopState _self;
  final $Res Function(_ConversationStopState) _then;

/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? origin = freezed,Object? executionId = freezed,Object? operation = freezed,Object? result = freezed,Object? localError = freezed,Object? observationError = freezed,}) {
  return _then(_ConversationStopState(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,origin: freezed == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,executionId: freezed == executionId ? _self.executionId : executionId // ignore: cast_nullable_to_non_nullable
as String?,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as CommandResult<Unit>?,localError: freezed == localError ? _self.localError : localError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get origin {
    if (_self.origin == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.origin!, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommandResultCopyWith<Unit, $Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $CommandResultCopyWith<Unit, $Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get localError {
    if (_self.localError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.localError!, (value) {
    return _then(_self.copyWith(localError: value));
  });
}/// Create a copy of ConversationStopState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get observationError {
    if (_self.observationError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.observationError!, (value) {
    return _then(_self.copyWith(observationError: value));
  });
}
}

/// @nodoc
mixin _$ConversationContinuationState {

 int get intent; ThreadFacetStamp get origin; String get continuationId; int get modelRouteRevision; OperationState? get operation; CommandResult<ContinueThreadReply>? get result; ContinuationOperationView? get recovered; StudioFailure? get error; bool get reading;
/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationContinuationStateCopyWith<ConversationContinuationState> get copyWith => _$ConversationContinuationStateCopyWithImpl<ConversationContinuationState>(this as ConversationContinuationState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConversationContinuationState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationContinuationState&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.continuationId, _this.continuationId) || other.continuationId == _this.continuationId)&&(identical(other.modelRouteRevision, _this.modelRouteRevision) || other.modelRouteRevision == _this.modelRouteRevision)&&(identical(other.operation, _this.operation) || other.operation == _this.operation)&&(identical(other.result, _this.result) || other.result == _this.result)&&(identical(other.recovered, _this.recovered) || other.recovered == _this.recovered)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.reading, _this.reading) || other.reading == _this.reading));
}


@override
int get hashCode {
  final _this = this as ConversationContinuationState;
  return Object.hash(runtimeType,_this.intent,_this.origin,_this.continuationId,_this.modelRouteRevision,_this.operation,_this.result,_this.recovered,_this.error,_this.reading);
}



}

/// @nodoc
abstract mixin class $ConversationContinuationStateCopyWith<$Res>  {
  factory $ConversationContinuationStateCopyWith(ConversationContinuationState value, $Res Function(ConversationContinuationState) _then) = _$ConversationContinuationStateCopyWithImpl;
@useResult
$Res call({
 int intent, ThreadFacetStamp origin, String continuationId, int modelRouteRevision, OperationState? operation, CommandResult<ContinueThreadReply>? result, ContinuationOperationView? recovered, StudioFailure? error, bool reading
});


$ThreadFacetStampCopyWith<$Res> get origin;$OperationStateCopyWith<$Res>? get operation;$CommandResultCopyWith<ContinueThreadReply, $Res>? get result;$ContinuationOperationViewCopyWith<$Res>? get recovered;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$ConversationContinuationStateCopyWithImpl<$Res>
    implements $ConversationContinuationStateCopyWith<$Res> {
  _$ConversationContinuationStateCopyWithImpl(this._self, this._then);

  final ConversationContinuationState _self;
  final $Res Function(ConversationContinuationState) _then;

/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,Object? origin = null,Object? continuationId = null,Object? modelRouteRevision = null,Object? operation = freezed,Object? result = freezed,Object? recovered = freezed,Object? error = freezed,Object? reading = null,}) {
  return _then(ConversationContinuationState(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,continuationId: null == continuationId ? _self.continuationId : continuationId // ignore: cast_nullable_to_non_nullable
as String,modelRouteRevision: null == modelRouteRevision ? _self.modelRouteRevision : modelRouteRevision // ignore: cast_nullable_to_non_nullable
as int,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as CommandResult<ContinueThreadReply>?,recovered: freezed == recovered ? _self.recovered : recovered // ignore: cast_nullable_to_non_nullable
as ContinuationOperationView?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get origin {

  return $ThreadFacetStampCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommandResultCopyWith<ContinueThreadReply, $Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $CommandResultCopyWith<ContinueThreadReply, $Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContinuationOperationViewCopyWith<$Res>? get recovered {
    if (_self.recovered == null) {
    return null;
  }

  return $ContinuationOperationViewCopyWith<$Res>(_self.recovered!, (value) {
    return _then(_self.copyWith(recovered: value));
  });
}/// Create a copy of ConversationContinuationState
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


/// Adds pattern-matching-related methods to [ConversationContinuationState].
extension ConversationContinuationStatePatterns on ConversationContinuationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationContinuationState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationContinuationState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationContinuationState value)  $default,){
final _that = this;
switch (_that) {
case _ConversationContinuationState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationContinuationState value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationContinuationState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int intent,  ThreadFacetStamp origin,  String continuationId,  int modelRouteRevision,  OperationState? operation,  CommandResult<ContinueThreadReply>? result,  ContinuationOperationView? recovered,  StudioFailure? error,  bool reading)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationContinuationState() when $default != null:
return $default(_that.intent,_that.origin,_that.continuationId,_that.modelRouteRevision,_that.operation,_that.result,_that.recovered,_that.error,_that.reading);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int intent,  ThreadFacetStamp origin,  String continuationId,  int modelRouteRevision,  OperationState? operation,  CommandResult<ContinueThreadReply>? result,  ContinuationOperationView? recovered,  StudioFailure? error,  bool reading)  $default,) {final _that = this;
switch (_that) {
case _ConversationContinuationState():
return $default(_that.intent,_that.origin,_that.continuationId,_that.modelRouteRevision,_that.operation,_that.result,_that.recovered,_that.error,_that.reading);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int intent,  ThreadFacetStamp origin,  String continuationId,  int modelRouteRevision,  OperationState? operation,  CommandResult<ContinueThreadReply>? result,  ContinuationOperationView? recovered,  StudioFailure? error,  bool reading)?  $default,) {final _that = this;
switch (_that) {
case _ConversationContinuationState() when $default != null:
return $default(_that.intent,_that.origin,_that.continuationId,_that.modelRouteRevision,_that.operation,_that.result,_that.recovered,_that.error,_that.reading);case _:
  return null;

}
}

}

/// @nodoc


class _ConversationContinuationState extends ConversationContinuationState {
  const _ConversationContinuationState({required this.intent, required this.origin, required this.continuationId, required this.modelRouteRevision, this.operation, this.result, this.recovered, this.error, this.reading = false}): super._();


@override final  int intent;
@override final  ThreadFacetStamp origin;
@override final  String continuationId;
@override final  int modelRouteRevision;
@override final  OperationState? operation;
@override final  CommandResult<ContinueThreadReply>? result;
@override final  ContinuationOperationView? recovered;
@override final  StudioFailure? error;
@override@JsonKey() final  bool reading;

/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationContinuationStateCopyWith<_ConversationContinuationState> get copyWith => __$ConversationContinuationStateCopyWithImpl<_ConversationContinuationState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationContinuationState&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.continuationId, continuationId) || other.continuationId == continuationId)&&(identical(other.modelRouteRevision, modelRouteRevision) || other.modelRouteRevision == modelRouteRevision)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.result, result) || other.result == result)&&(identical(other.recovered, recovered) || other.recovered == recovered)&&(identical(other.error, error) || other.error == error)&&(identical(other.reading, reading) || other.reading == reading));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,origin,continuationId,modelRouteRevision,operation,result,recovered,error,reading);
}



}

/// @nodoc
abstract mixin class _$ConversationContinuationStateCopyWith<$Res> implements $ConversationContinuationStateCopyWith<$Res> {
  factory _$ConversationContinuationStateCopyWith(_ConversationContinuationState value, $Res Function(_ConversationContinuationState) _then) = __$ConversationContinuationStateCopyWithImpl;
@override @useResult
$Res call({
 int intent, ThreadFacetStamp origin, String continuationId, int modelRouteRevision, OperationState? operation, CommandResult<ContinueThreadReply>? result, ContinuationOperationView? recovered, StudioFailure? error, bool reading
});


@override $ThreadFacetStampCopyWith<$Res> get origin;@override $OperationStateCopyWith<$Res>? get operation;@override $CommandResultCopyWith<ContinueThreadReply, $Res>? get result;@override $ContinuationOperationViewCopyWith<$Res>? get recovered;@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$ConversationContinuationStateCopyWithImpl<$Res>
    implements _$ConversationContinuationStateCopyWith<$Res> {
  __$ConversationContinuationStateCopyWithImpl(this._self, this._then);

  final _ConversationContinuationState _self;
  final $Res Function(_ConversationContinuationState) _then;

/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? origin = null,Object? continuationId = null,Object? modelRouteRevision = null,Object? operation = freezed,Object? result = freezed,Object? recovered = freezed,Object? error = freezed,Object? reading = null,}) {
  return _then(_ConversationContinuationState(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,continuationId: null == continuationId ? _self.continuationId : continuationId // ignore: cast_nullable_to_non_nullable
as String,modelRouteRevision: null == modelRouteRevision ? _self.modelRouteRevision : modelRouteRevision // ignore: cast_nullable_to_non_nullable
as int,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as CommandResult<ContinueThreadReply>?,recovered: freezed == recovered ? _self.recovered : recovered // ignore: cast_nullable_to_non_nullable
as ContinuationOperationView?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get origin {

  return $ThreadFacetStampCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommandResultCopyWith<ContinueThreadReply, $Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $CommandResultCopyWith<ContinueThreadReply, $Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}/// Create a copy of ConversationContinuationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContinuationOperationViewCopyWith<$Res>? get recovered {
    if (_self.recovered == null) {
    return null;
  }

  return $ContinuationOperationViewCopyWith<$Res>(_self.recovered!, (value) {
    return _then(_self.copyWith(recovered: value));
  });
}/// Create a copy of ConversationContinuationState
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
