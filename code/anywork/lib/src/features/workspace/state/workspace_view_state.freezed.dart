// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workspace_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WorkspaceNavigationIntent {

 int get serial; WorkspaceNavigationDestination get destination;
/// Create a copy of WorkspaceNavigationIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceNavigationIntentCopyWith<WorkspaceNavigationIntent> get copyWith => _$WorkspaceNavigationIntentCopyWithImpl<WorkspaceNavigationIntent>(this as WorkspaceNavigationIntent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceNavigationIntent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceNavigationIntent&&(identical(other.serial, _this.serial) || other.serial == _this.serial)&&(identical(other.destination, _this.destination) || other.destination == _this.destination));
}


@override
int get hashCode {
  final _this = this as WorkspaceNavigationIntent;
  return Object.hash(runtimeType,_this.serial,_this.destination);
}

@override
String toString() {
  final _this = this as WorkspaceNavigationIntent;
  return 'WorkspaceNavigationIntent(serial: ${_this.serial}, destination: ${_this.destination})';
}


}

/// @nodoc
abstract mixin class $WorkspaceNavigationIntentCopyWith<$Res>  {
  factory $WorkspaceNavigationIntentCopyWith(WorkspaceNavigationIntent value, $Res Function(WorkspaceNavigationIntent) _then) = _$WorkspaceNavigationIntentCopyWithImpl;
@useResult
$Res call({
 int serial, WorkspaceNavigationDestination destination
});




}
/// @nodoc
class _$WorkspaceNavigationIntentCopyWithImpl<$Res>
    implements $WorkspaceNavigationIntentCopyWith<$Res> {
  _$WorkspaceNavigationIntentCopyWithImpl(this._self, this._then);

  final WorkspaceNavigationIntent _self;
  final $Res Function(WorkspaceNavigationIntent) _then;

/// Create a copy of WorkspaceNavigationIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? serial = null,Object? destination = null,}) {
  return _then(WorkspaceNavigationIntent(
serial: null == serial ? _self.serial : serial // ignore: cast_nullable_to_non_nullable
as int,destination: null == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as WorkspaceNavigationDestination,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkspaceNavigationIntent].
extension WorkspaceNavigationIntentPatterns on WorkspaceNavigationIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceNavigationIntent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceNavigationIntent() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceNavigationIntent value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceNavigationIntent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceNavigationIntent value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceNavigationIntent() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int serial,  WorkspaceNavigationDestination destination)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceNavigationIntent() when $default != null:
return $default(_that.serial,_that.destination);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int serial,  WorkspaceNavigationDestination destination)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceNavigationIntent():
return $default(_that.serial,_that.destination);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int serial,  WorkspaceNavigationDestination destination)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceNavigationIntent() when $default != null:
return $default(_that.serial,_that.destination);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceNavigationIntent implements WorkspaceNavigationIntent {
  const _WorkspaceNavigationIntent({required this.serial, required this.destination});


@override final  int serial;
@override final  WorkspaceNavigationDestination destination;

/// Create a copy of WorkspaceNavigationIntent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceNavigationIntentCopyWith<_WorkspaceNavigationIntent> get copyWith => __$WorkspaceNavigationIntentCopyWithImpl<_WorkspaceNavigationIntent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceNavigationIntent&&(identical(other.serial, serial) || other.serial == serial)&&(identical(other.destination, destination) || other.destination == destination));
}


@override
int get hashCode {
    return Object.hash(runtimeType,serial,destination);
}

@override
String toString() {
    return 'WorkspaceNavigationIntent(serial: $serial, destination: $destination)';
}


}

/// @nodoc
abstract mixin class _$WorkspaceNavigationIntentCopyWith<$Res> implements $WorkspaceNavigationIntentCopyWith<$Res> {
  factory _$WorkspaceNavigationIntentCopyWith(_WorkspaceNavigationIntent value, $Res Function(_WorkspaceNavigationIntent) _then) = __$WorkspaceNavigationIntentCopyWithImpl;
@override @useResult
$Res call({
 int serial, WorkspaceNavigationDestination destination
});




}
/// @nodoc
class __$WorkspaceNavigationIntentCopyWithImpl<$Res>
    implements _$WorkspaceNavigationIntentCopyWith<$Res> {
  __$WorkspaceNavigationIntentCopyWithImpl(this._self, this._then);

  final _WorkspaceNavigationIntent _self;
  final $Res Function(_WorkspaceNavigationIntent) _then;

/// Create a copy of WorkspaceNavigationIntent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? serial = null,Object? destination = null,}) {
  return _then(_WorkspaceNavigationIntent(
serial: null == serial ? _self.serial : serial // ignore: cast_nullable_to_non_nullable
as int,destination: null == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as WorkspaceNavigationDestination,
  ));
}


}

/// @nodoc
mixin _$WorkspaceActionPresentation {

 int get intent; bool get waiting; OperationState? get operation; StudioFailure? get admissionError; StudioFailure? get observationError;
/// Create a copy of WorkspaceActionPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceActionPresentationCopyWith<WorkspaceActionPresentation> get copyWith => _$WorkspaceActionPresentationCopyWithImpl<WorkspaceActionPresentation>(this as WorkspaceActionPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceActionPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceActionPresentation&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.waiting, _this.waiting) || other.waiting == _this.waiting)&&(identical(other.operation, _this.operation) || other.operation == _this.operation)&&(identical(other.admissionError, _this.admissionError) || other.admissionError == _this.admissionError)&&(identical(other.observationError, _this.observationError) || other.observationError == _this.observationError));
}


@override
int get hashCode {
  final _this = this as WorkspaceActionPresentation;
  return Object.hash(runtimeType,_this.intent,_this.waiting,_this.operation,_this.admissionError,_this.observationError);
}



}

/// @nodoc
abstract mixin class $WorkspaceActionPresentationCopyWith<$Res>  {
  factory $WorkspaceActionPresentationCopyWith(WorkspaceActionPresentation value, $Res Function(WorkspaceActionPresentation) _then) = _$WorkspaceActionPresentationCopyWithImpl;
@useResult
$Res call({
 int intent, bool waiting, OperationState? operation, StudioFailure? admissionError, StudioFailure? observationError
});


$OperationStateCopyWith<$Res>? get operation;$StudioFailureCopyWith<$Res>? get admissionError;$StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class _$WorkspaceActionPresentationCopyWithImpl<$Res>
    implements $WorkspaceActionPresentationCopyWith<$Res> {
  _$WorkspaceActionPresentationCopyWithImpl(this._self, this._then);

  final WorkspaceActionPresentation _self;
  final $Res Function(WorkspaceActionPresentation) _then;

/// Create a copy of WorkspaceActionPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,Object? waiting = null,Object? operation = freezed,Object? admissionError = freezed,Object? observationError = freezed,}) {
  return _then(WorkspaceActionPresentation(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,waiting: null == waiting ? _self.waiting : waiting // ignore: cast_nullable_to_non_nullable
as bool,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,admissionError: freezed == admissionError ? _self.admissionError : admissionError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of WorkspaceActionPresentation
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
}/// Create a copy of WorkspaceActionPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get admissionError {
    if (_self.admissionError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.admissionError!, (value) {
    return _then(_self.copyWith(admissionError: value));
  });
}/// Create a copy of WorkspaceActionPresentation
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


/// Adds pattern-matching-related methods to [WorkspaceActionPresentation].
extension WorkspaceActionPresentationPatterns on WorkspaceActionPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceActionPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceActionPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceActionPresentation value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceActionPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceActionPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceActionPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int intent,  bool waiting,  OperationState? operation,  StudioFailure? admissionError,  StudioFailure? observationError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceActionPresentation() when $default != null:
return $default(_that.intent,_that.waiting,_that.operation,_that.admissionError,_that.observationError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int intent,  bool waiting,  OperationState? operation,  StudioFailure? admissionError,  StudioFailure? observationError)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceActionPresentation():
return $default(_that.intent,_that.waiting,_that.operation,_that.admissionError,_that.observationError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int intent,  bool waiting,  OperationState? operation,  StudioFailure? admissionError,  StudioFailure? observationError)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceActionPresentation() when $default != null:
return $default(_that.intent,_that.waiting,_that.operation,_that.admissionError,_that.observationError);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceActionPresentation implements WorkspaceActionPresentation {
  const _WorkspaceActionPresentation({required this.intent, required this.waiting, required this.operation, required this.admissionError, this.observationError});


@override final  int intent;
@override final  bool waiting;
@override final  OperationState? operation;
@override final  StudioFailure? admissionError;
@override final  StudioFailure? observationError;

/// Create a copy of WorkspaceActionPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceActionPresentationCopyWith<_WorkspaceActionPresentation> get copyWith => __$WorkspaceActionPresentationCopyWithImpl<_WorkspaceActionPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceActionPresentation&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.waiting, waiting) || other.waiting == waiting)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.admissionError, admissionError) || other.admissionError == admissionError)&&(identical(other.observationError, observationError) || other.observationError == observationError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,waiting,operation,admissionError,observationError);
}



}

/// @nodoc
abstract mixin class _$WorkspaceActionPresentationCopyWith<$Res> implements $WorkspaceActionPresentationCopyWith<$Res> {
  factory _$WorkspaceActionPresentationCopyWith(_WorkspaceActionPresentation value, $Res Function(_WorkspaceActionPresentation) _then) = __$WorkspaceActionPresentationCopyWithImpl;
@override @useResult
$Res call({
 int intent, bool waiting, OperationState? operation, StudioFailure? admissionError, StudioFailure? observationError
});


@override $OperationStateCopyWith<$Res>? get operation;@override $StudioFailureCopyWith<$Res>? get admissionError;@override $StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class __$WorkspaceActionPresentationCopyWithImpl<$Res>
    implements _$WorkspaceActionPresentationCopyWith<$Res> {
  __$WorkspaceActionPresentationCopyWithImpl(this._self, this._then);

  final _WorkspaceActionPresentation _self;
  final $Res Function(_WorkspaceActionPresentation) _then;

/// Create a copy of WorkspaceActionPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? waiting = null,Object? operation = freezed,Object? admissionError = freezed,Object? observationError = freezed,}) {
  return _then(_WorkspaceActionPresentation(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,waiting: null == waiting ? _self.waiting : waiting // ignore: cast_nullable_to_non_nullable
as bool,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,admissionError: freezed == admissionError ? _self.admissionError : admissionError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of WorkspaceActionPresentation
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
}/// Create a copy of WorkspaceActionPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get admissionError {
    if (_self.admissionError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.admissionError!, (value) {
    return _then(_self.copyWith(admissionError: value));
  });
}/// Create a copy of WorkspaceActionPresentation
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
mixin _$WorkspaceNameEditor {

 int get serial; WorkspaceNameTarget get target; String get id; String get raw; WorkspaceNameProblem? get problem; bool get saving; StudioFailure? get error;
/// Create a copy of WorkspaceNameEditor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceNameEditorCopyWith<WorkspaceNameEditor> get copyWith => _$WorkspaceNameEditorCopyWithImpl<WorkspaceNameEditor>(this as WorkspaceNameEditor, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceNameEditor;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceNameEditor&&(identical(other.serial, _this.serial) || other.serial == _this.serial)&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.raw, _this.raw) || other.raw == _this.raw)&&(identical(other.problem, _this.problem) || other.problem == _this.problem)&&(identical(other.saving, _this.saving) || other.saving == _this.saving)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as WorkspaceNameEditor;
  return Object.hash(runtimeType,_this.serial,_this.target,_this.id,_this.raw,_this.problem,_this.saving,_this.error);
}



}

/// @nodoc
abstract mixin class $WorkspaceNameEditorCopyWith<$Res>  {
  factory $WorkspaceNameEditorCopyWith(WorkspaceNameEditor value, $Res Function(WorkspaceNameEditor) _then) = _$WorkspaceNameEditorCopyWithImpl;
@useResult
$Res call({
 int serial, WorkspaceNameTarget target, String id, String raw, WorkspaceNameProblem? problem, bool saving, StudioFailure? error
});


$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$WorkspaceNameEditorCopyWithImpl<$Res>
    implements $WorkspaceNameEditorCopyWith<$Res> {
  _$WorkspaceNameEditorCopyWithImpl(this._self, this._then);

  final WorkspaceNameEditor _self;
  final $Res Function(WorkspaceNameEditor) _then;

/// Create a copy of WorkspaceNameEditor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? serial = null,Object? target = null,Object? id = null,Object? raw = null,Object? problem = freezed,Object? saving = null,Object? error = freezed,}) {
  return _then(WorkspaceNameEditor(
serial: null == serial ? _self.serial : serial // ignore: cast_nullable_to_non_nullable
as int,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as WorkspaceNameTarget,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,problem: freezed == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as WorkspaceNameProblem?,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of WorkspaceNameEditor
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


/// Adds pattern-matching-related methods to [WorkspaceNameEditor].
extension WorkspaceNameEditorPatterns on WorkspaceNameEditor {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceNameEditor value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceNameEditor() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceNameEditor value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceNameEditor():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceNameEditor value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceNameEditor() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int serial,  WorkspaceNameTarget target,  String id,  String raw,  WorkspaceNameProblem? problem,  bool saving,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceNameEditor() when $default != null:
return $default(_that.serial,_that.target,_that.id,_that.raw,_that.problem,_that.saving,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int serial,  WorkspaceNameTarget target,  String id,  String raw,  WorkspaceNameProblem? problem,  bool saving,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceNameEditor():
return $default(_that.serial,_that.target,_that.id,_that.raw,_that.problem,_that.saving,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int serial,  WorkspaceNameTarget target,  String id,  String raw,  WorkspaceNameProblem? problem,  bool saving,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceNameEditor() when $default != null:
return $default(_that.serial,_that.target,_that.id,_that.raw,_that.problem,_that.saving,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceNameEditor implements WorkspaceNameEditor {
  const _WorkspaceNameEditor({required this.serial, required this.target, required this.id, required this.raw, required this.problem, required this.saving, required this.error});


@override final  int serial;
@override final  WorkspaceNameTarget target;
@override final  String id;
@override final  String raw;
@override final  WorkspaceNameProblem? problem;
@override final  bool saving;
@override final  StudioFailure? error;

/// Create a copy of WorkspaceNameEditor
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceNameEditorCopyWith<_WorkspaceNameEditor> get copyWith => __$WorkspaceNameEditorCopyWithImpl<_WorkspaceNameEditor>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceNameEditor&&(identical(other.serial, serial) || other.serial == serial)&&(identical(other.target, target) || other.target == target)&&(identical(other.id, id) || other.id == id)&&(identical(other.raw, raw) || other.raw == raw)&&(identical(other.problem, problem) || other.problem == problem)&&(identical(other.saving, saving) || other.saving == saving)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,serial,target,id,raw,problem,saving,error);
}



}

/// @nodoc
abstract mixin class _$WorkspaceNameEditorCopyWith<$Res> implements $WorkspaceNameEditorCopyWith<$Res> {
  factory _$WorkspaceNameEditorCopyWith(_WorkspaceNameEditor value, $Res Function(_WorkspaceNameEditor) _then) = __$WorkspaceNameEditorCopyWithImpl;
@override @useResult
$Res call({
 int serial, WorkspaceNameTarget target, String id, String raw, WorkspaceNameProblem? problem, bool saving, StudioFailure? error
});


@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$WorkspaceNameEditorCopyWithImpl<$Res>
    implements _$WorkspaceNameEditorCopyWith<$Res> {
  __$WorkspaceNameEditorCopyWithImpl(this._self, this._then);

  final _WorkspaceNameEditor _self;
  final $Res Function(_WorkspaceNameEditor) _then;

/// Create a copy of WorkspaceNameEditor
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? serial = null,Object? target = null,Object? id = null,Object? raw = null,Object? problem = freezed,Object? saving = null,Object? error = freezed,}) {
  return _then(_WorkspaceNameEditor(
serial: null == serial ? _self.serial : serial // ignore: cast_nullable_to_non_nullable
as int,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as WorkspaceNameTarget,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,problem: freezed == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as WorkspaceNameProblem?,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of WorkspaceNameEditor
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

/// @nodoc
mixin _$WorkspaceViewState {

 WorkspaceState get workspace; ConversationActivationFailure? get activationFailure; ProjectDirectoryState get projects; AgentDirectoryState get agents; ProjectRecord? get selectedProject; bool get projectLoading; StudioFailure? get projectReadError; ThreadMetadataState? get selectedMetadata; StudioFailure? get metadataDemandError; Map<String, WorkspaceActionPresentation> get actions; WorkspaceOpenResult? get openResult; bool get opening; StudioFailure? get openAdmissionError; WorkspaceNavigationIntent? get navigation; WorkspaceNameEditor? get nameEditor;
/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceViewStateCopyWith<WorkspaceViewState> get copyWith => _$WorkspaceViewStateCopyWithImpl<WorkspaceViewState>(this as WorkspaceViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceViewState&&(identical(other.workspace, _this.workspace) || other.workspace == _this.workspace)&&(identical(other.activationFailure, _this.activationFailure) || other.activationFailure == _this.activationFailure)&&(identical(other.projects, _this.projects) || other.projects == _this.projects)&&(identical(other.agents, _this.agents) || other.agents == _this.agents)&&(identical(other.selectedProject, _this.selectedProject) || other.selectedProject == _this.selectedProject)&&(identical(other.projectLoading, _this.projectLoading) || other.projectLoading == _this.projectLoading)&&(identical(other.projectReadError, _this.projectReadError) || other.projectReadError == _this.projectReadError)&&(identical(other.selectedMetadata, _this.selectedMetadata) || other.selectedMetadata == _this.selectedMetadata)&&(identical(other.metadataDemandError, _this.metadataDemandError) || other.metadataDemandError == _this.metadataDemandError)&&const DeepCollectionEquality().equals(other.actions, _this.actions)&&(identical(other.openResult, _this.openResult) || other.openResult == _this.openResult)&&(identical(other.opening, _this.opening) || other.opening == _this.opening)&&(identical(other.openAdmissionError, _this.openAdmissionError) || other.openAdmissionError == _this.openAdmissionError)&&(identical(other.navigation, _this.navigation) || other.navigation == _this.navigation)&&(identical(other.nameEditor, _this.nameEditor) || other.nameEditor == _this.nameEditor));
}


@override
int get hashCode {
  final _this = this as WorkspaceViewState;
  return Object.hash(runtimeType,_this.workspace,_this.activationFailure,_this.projects,_this.agents,_this.selectedProject,_this.projectLoading,_this.projectReadError,_this.selectedMetadata,_this.metadataDemandError,const DeepCollectionEquality().hash(_this.actions),_this.openResult,_this.opening,_this.openAdmissionError,_this.navigation,_this.nameEditor);
}



}

/// @nodoc
abstract mixin class $WorkspaceViewStateCopyWith<$Res>  {
  factory $WorkspaceViewStateCopyWith(WorkspaceViewState value, $Res Function(WorkspaceViewState) _then) = _$WorkspaceViewStateCopyWithImpl;
@useResult
$Res call({
 WorkspaceState workspace, ConversationActivationFailure? activationFailure, ProjectDirectoryState projects, AgentDirectoryState agents, ProjectRecord? selectedProject, bool projectLoading, StudioFailure? projectReadError, ThreadMetadataState? selectedMetadata, StudioFailure? metadataDemandError, Map<String, WorkspaceActionPresentation> actions, WorkspaceOpenResult? openResult, bool opening, StudioFailure? openAdmissionError, WorkspaceNavigationIntent? navigation, WorkspaceNameEditor? nameEditor
});


$WorkspaceStateCopyWith<$Res> get workspace;$ConversationActivationFailureCopyWith<$Res>? get activationFailure;$ProjectDirectoryStateCopyWith<$Res> get projects;$AgentDirectoryStateCopyWith<$Res> get agents;$ProjectRecordCopyWith<$Res>? get selectedProject;$StudioFailureCopyWith<$Res>? get projectReadError;$ThreadMetadataStateCopyWith<$Res>? get selectedMetadata;$StudioFailureCopyWith<$Res>? get metadataDemandError;$WorkspaceOpenResultCopyWith<$Res>? get openResult;$StudioFailureCopyWith<$Res>? get openAdmissionError;$WorkspaceNavigationIntentCopyWith<$Res>? get navigation;$WorkspaceNameEditorCopyWith<$Res>? get nameEditor;

}
/// @nodoc
class _$WorkspaceViewStateCopyWithImpl<$Res>
    implements $WorkspaceViewStateCopyWith<$Res> {
  _$WorkspaceViewStateCopyWithImpl(this._self, this._then);

  final WorkspaceViewState _self;
  final $Res Function(WorkspaceViewState) _then;

/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? workspace = null,Object? activationFailure = freezed,Object? projects = null,Object? agents = null,Object? selectedProject = freezed,Object? projectLoading = null,Object? projectReadError = freezed,Object? selectedMetadata = freezed,Object? metadataDemandError = freezed,Object? actions = null,Object? openResult = freezed,Object? opening = null,Object? openAdmissionError = freezed,Object? navigation = freezed,Object? nameEditor = freezed,}) {
  return _then(WorkspaceViewState(
workspace: null == workspace ? _self.workspace : workspace // ignore: cast_nullable_to_non_nullable
as WorkspaceState,activationFailure: freezed == activationFailure ? _self.activationFailure : activationFailure // ignore: cast_nullable_to_non_nullable
as ConversationActivationFailure?,projects: null == projects ? _self.projects : projects // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryState,agents: null == agents ? _self.agents : agents // ignore: cast_nullable_to_non_nullable
as AgentDirectoryState,selectedProject: freezed == selectedProject ? _self.selectedProject : selectedProject // ignore: cast_nullable_to_non_nullable
as ProjectRecord?,projectLoading: null == projectLoading ? _self.projectLoading : projectLoading // ignore: cast_nullable_to_non_nullable
as bool,projectReadError: freezed == projectReadError ? _self.projectReadError : projectReadError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,selectedMetadata: freezed == selectedMetadata ? _self.selectedMetadata : selectedMetadata // ignore: cast_nullable_to_non_nullable
as ThreadMetadataState?,metadataDemandError: freezed == metadataDemandError ? _self.metadataDemandError : metadataDemandError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as Map<String, WorkspaceActionPresentation>,openResult: freezed == openResult ? _self.openResult : openResult // ignore: cast_nullable_to_non_nullable
as WorkspaceOpenResult?,opening: null == opening ? _self.opening : opening // ignore: cast_nullable_to_non_nullable
as bool,openAdmissionError: freezed == openAdmissionError ? _self.openAdmissionError : openAdmissionError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,navigation: freezed == navigation ? _self.navigation : navigation // ignore: cast_nullable_to_non_nullable
as WorkspaceNavigationIntent?,nameEditor: freezed == nameEditor ? _self.nameEditor : nameEditor // ignore: cast_nullable_to_non_nullable
as WorkspaceNameEditor?,
  ));
}
/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceStateCopyWith<$Res> get workspace {

  return $WorkspaceStateCopyWith<$Res>(_self.workspace, (value) {
    return _then(_self.copyWith(workspace: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationActivationFailureCopyWith<$Res>? get activationFailure {
    if (_self.activationFailure == null) {
    return null;
  }

  return $ConversationActivationFailureCopyWith<$Res>(_self.activationFailure!, (value) {
    return _then(_self.copyWith(activationFailure: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryStateCopyWith<$Res> get projects {

  return $ProjectDirectoryStateCopyWith<$Res>(_self.projects, (value) {
    return _then(_self.copyWith(projects: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryStateCopyWith<$Res> get agents {

  return $AgentDirectoryStateCopyWith<$Res>(_self.agents, (value) {
    return _then(_self.copyWith(agents: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectRecordCopyWith<$Res>? get selectedProject {
    if (_self.selectedProject == null) {
    return null;
  }

  return $ProjectRecordCopyWith<$Res>(_self.selectedProject!, (value) {
    return _then(_self.copyWith(selectedProject: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get projectReadError {
    if (_self.projectReadError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.projectReadError!, (value) {
    return _then(_self.copyWith(projectReadError: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetadataStateCopyWith<$Res>? get selectedMetadata {
    if (_self.selectedMetadata == null) {
    return null;
  }

  return $ThreadMetadataStateCopyWith<$Res>(_self.selectedMetadata!, (value) {
    return _then(_self.copyWith(selectedMetadata: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get metadataDemandError {
    if (_self.metadataDemandError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.metadataDemandError!, (value) {
    return _then(_self.copyWith(metadataDemandError: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceOpenResultCopyWith<$Res>? get openResult {
    if (_self.openResult == null) {
    return null;
  }

  return $WorkspaceOpenResultCopyWith<$Res>(_self.openResult!, (value) {
    return _then(_self.copyWith(openResult: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get openAdmissionError {
    if (_self.openAdmissionError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.openAdmissionError!, (value) {
    return _then(_self.copyWith(openAdmissionError: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceNavigationIntentCopyWith<$Res>? get navigation {
    if (_self.navigation == null) {
    return null;
  }

  return $WorkspaceNavigationIntentCopyWith<$Res>(_self.navigation!, (value) {
    return _then(_self.copyWith(navigation: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceNameEditorCopyWith<$Res>? get nameEditor {
    if (_self.nameEditor == null) {
    return null;
  }

  return $WorkspaceNameEditorCopyWith<$Res>(_self.nameEditor!, (value) {
    return _then(_self.copyWith(nameEditor: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkspaceViewState].
extension WorkspaceViewStatePatterns on WorkspaceViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceViewState value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceViewState value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WorkspaceState workspace,  ConversationActivationFailure? activationFailure,  ProjectDirectoryState projects,  AgentDirectoryState agents,  ProjectRecord? selectedProject,  bool projectLoading,  StudioFailure? projectReadError,  ThreadMetadataState? selectedMetadata,  StudioFailure? metadataDemandError,  Map<String, WorkspaceActionPresentation> actions,  WorkspaceOpenResult? openResult,  bool opening,  StudioFailure? openAdmissionError,  WorkspaceNavigationIntent? navigation,  WorkspaceNameEditor? nameEditor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceViewState() when $default != null:
return $default(_that.workspace,_that.activationFailure,_that.projects,_that.agents,_that.selectedProject,_that.projectLoading,_that.projectReadError,_that.selectedMetadata,_that.metadataDemandError,_that.actions,_that.openResult,_that.opening,_that.openAdmissionError,_that.navigation,_that.nameEditor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WorkspaceState workspace,  ConversationActivationFailure? activationFailure,  ProjectDirectoryState projects,  AgentDirectoryState agents,  ProjectRecord? selectedProject,  bool projectLoading,  StudioFailure? projectReadError,  ThreadMetadataState? selectedMetadata,  StudioFailure? metadataDemandError,  Map<String, WorkspaceActionPresentation> actions,  WorkspaceOpenResult? openResult,  bool opening,  StudioFailure? openAdmissionError,  WorkspaceNavigationIntent? navigation,  WorkspaceNameEditor? nameEditor)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceViewState():
return $default(_that.workspace,_that.activationFailure,_that.projects,_that.agents,_that.selectedProject,_that.projectLoading,_that.projectReadError,_that.selectedMetadata,_that.metadataDemandError,_that.actions,_that.openResult,_that.opening,_that.openAdmissionError,_that.navigation,_that.nameEditor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WorkspaceState workspace,  ConversationActivationFailure? activationFailure,  ProjectDirectoryState projects,  AgentDirectoryState agents,  ProjectRecord? selectedProject,  bool projectLoading,  StudioFailure? projectReadError,  ThreadMetadataState? selectedMetadata,  StudioFailure? metadataDemandError,  Map<String, WorkspaceActionPresentation> actions,  WorkspaceOpenResult? openResult,  bool opening,  StudioFailure? openAdmissionError,  WorkspaceNavigationIntent? navigation,  WorkspaceNameEditor? nameEditor)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceViewState() when $default != null:
return $default(_that.workspace,_that.activationFailure,_that.projects,_that.agents,_that.selectedProject,_that.projectLoading,_that.projectReadError,_that.selectedMetadata,_that.metadataDemandError,_that.actions,_that.openResult,_that.opening,_that.openAdmissionError,_that.navigation,_that.nameEditor);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceViewState implements WorkspaceViewState {
  const _WorkspaceViewState({required this.workspace, required this.activationFailure, required this.projects, required this.agents, required this.selectedProject, required this.projectLoading, required this.projectReadError, required this.selectedMetadata, required this.metadataDemandError, required  Map<String, WorkspaceActionPresentation> actions, required this.openResult, required this.opening, required this.openAdmissionError, required this.navigation, required this.nameEditor}): _actions = actions;


@override final  WorkspaceState workspace;
@override final  ConversationActivationFailure? activationFailure;
@override final  ProjectDirectoryState projects;
@override final  AgentDirectoryState agents;
@override final  ProjectRecord? selectedProject;
@override final  bool projectLoading;
@override final  StudioFailure? projectReadError;
@override final  ThreadMetadataState? selectedMetadata;
@override final  StudioFailure? metadataDemandError;
 final  Map<String, WorkspaceActionPresentation> _actions;
@override Map<String, WorkspaceActionPresentation> get actions {
  if (_actions is EqualUnmodifiableMapView) return _actions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_actions);
}

@override final  WorkspaceOpenResult? openResult;
@override final  bool opening;
@override final  StudioFailure? openAdmissionError;
@override final  WorkspaceNavigationIntent? navigation;
@override final  WorkspaceNameEditor? nameEditor;

/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceViewStateCopyWith<_WorkspaceViewState> get copyWith => __$WorkspaceViewStateCopyWithImpl<_WorkspaceViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceViewState&&(identical(other.workspace, workspace) || other.workspace == workspace)&&(identical(other.activationFailure, activationFailure) || other.activationFailure == activationFailure)&&(identical(other.projects, projects) || other.projects == projects)&&(identical(other.agents, agents) || other.agents == agents)&&(identical(other.selectedProject, selectedProject) || other.selectedProject == selectedProject)&&(identical(other.projectLoading, projectLoading) || other.projectLoading == projectLoading)&&(identical(other.projectReadError, projectReadError) || other.projectReadError == projectReadError)&&(identical(other.selectedMetadata, selectedMetadata) || other.selectedMetadata == selectedMetadata)&&(identical(other.metadataDemandError, metadataDemandError) || other.metadataDemandError == metadataDemandError)&&const DeepCollectionEquality().equals(other.actions, _actions)&&(identical(other.openResult, openResult) || other.openResult == openResult)&&(identical(other.opening, opening) || other.opening == opening)&&(identical(other.openAdmissionError, openAdmissionError) || other.openAdmissionError == openAdmissionError)&&(identical(other.navigation, navigation) || other.navigation == navigation)&&(identical(other.nameEditor, nameEditor) || other.nameEditor == nameEditor));
}


@override
int get hashCode {
    return Object.hash(runtimeType,workspace,activationFailure,projects,agents,selectedProject,projectLoading,projectReadError,selectedMetadata,metadataDemandError,const DeepCollectionEquality().hash(_actions),openResult,opening,openAdmissionError,navigation,nameEditor);
}



}

/// @nodoc
abstract mixin class _$WorkspaceViewStateCopyWith<$Res> implements $WorkspaceViewStateCopyWith<$Res> {
  factory _$WorkspaceViewStateCopyWith(_WorkspaceViewState value, $Res Function(_WorkspaceViewState) _then) = __$WorkspaceViewStateCopyWithImpl;
@override @useResult
$Res call({
 WorkspaceState workspace, ConversationActivationFailure? activationFailure, ProjectDirectoryState projects, AgentDirectoryState agents, ProjectRecord? selectedProject, bool projectLoading, StudioFailure? projectReadError, ThreadMetadataState? selectedMetadata, StudioFailure? metadataDemandError, Map<String, WorkspaceActionPresentation> actions, WorkspaceOpenResult? openResult, bool opening, StudioFailure? openAdmissionError, WorkspaceNavigationIntent? navigation, WorkspaceNameEditor? nameEditor
});


@override $WorkspaceStateCopyWith<$Res> get workspace;@override $ConversationActivationFailureCopyWith<$Res>? get activationFailure;@override $ProjectDirectoryStateCopyWith<$Res> get projects;@override $AgentDirectoryStateCopyWith<$Res> get agents;@override $ProjectRecordCopyWith<$Res>? get selectedProject;@override $StudioFailureCopyWith<$Res>? get projectReadError;@override $ThreadMetadataStateCopyWith<$Res>? get selectedMetadata;@override $StudioFailureCopyWith<$Res>? get metadataDemandError;@override $WorkspaceOpenResultCopyWith<$Res>? get openResult;@override $StudioFailureCopyWith<$Res>? get openAdmissionError;@override $WorkspaceNavigationIntentCopyWith<$Res>? get navigation;@override $WorkspaceNameEditorCopyWith<$Res>? get nameEditor;

}
/// @nodoc
class __$WorkspaceViewStateCopyWithImpl<$Res>
    implements _$WorkspaceViewStateCopyWith<$Res> {
  __$WorkspaceViewStateCopyWithImpl(this._self, this._then);

  final _WorkspaceViewState _self;
  final $Res Function(_WorkspaceViewState) _then;

/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? workspace = null,Object? activationFailure = freezed,Object? projects = null,Object? agents = null,Object? selectedProject = freezed,Object? projectLoading = null,Object? projectReadError = freezed,Object? selectedMetadata = freezed,Object? metadataDemandError = freezed,Object? actions = null,Object? openResult = freezed,Object? opening = null,Object? openAdmissionError = freezed,Object? navigation = freezed,Object? nameEditor = freezed,}) {
  return _then(_WorkspaceViewState(
workspace: null == workspace ? _self.workspace : workspace // ignore: cast_nullable_to_non_nullable
as WorkspaceState,activationFailure: freezed == activationFailure ? _self.activationFailure : activationFailure // ignore: cast_nullable_to_non_nullable
as ConversationActivationFailure?,projects: null == projects ? _self.projects : projects // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryState,agents: null == agents ? _self.agents : agents // ignore: cast_nullable_to_non_nullable
as AgentDirectoryState,selectedProject: freezed == selectedProject ? _self.selectedProject : selectedProject // ignore: cast_nullable_to_non_nullable
as ProjectRecord?,projectLoading: null == projectLoading ? _self.projectLoading : projectLoading // ignore: cast_nullable_to_non_nullable
as bool,projectReadError: freezed == projectReadError ? _self.projectReadError : projectReadError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,selectedMetadata: freezed == selectedMetadata ? _self.selectedMetadata : selectedMetadata // ignore: cast_nullable_to_non_nullable
as ThreadMetadataState?,metadataDemandError: freezed == metadataDemandError ? _self.metadataDemandError : metadataDemandError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,actions: null == actions ? _self._actions : actions // ignore: cast_nullable_to_non_nullable
as Map<String, WorkspaceActionPresentation>,openResult: freezed == openResult ? _self.openResult : openResult // ignore: cast_nullable_to_non_nullable
as WorkspaceOpenResult?,opening: null == opening ? _self.opening : opening // ignore: cast_nullable_to_non_nullable
as bool,openAdmissionError: freezed == openAdmissionError ? _self.openAdmissionError : openAdmissionError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,navigation: freezed == navigation ? _self.navigation : navigation // ignore: cast_nullable_to_non_nullable
as WorkspaceNavigationIntent?,nameEditor: freezed == nameEditor ? _self.nameEditor : nameEditor // ignore: cast_nullable_to_non_nullable
as WorkspaceNameEditor?,
  ));
}

/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceStateCopyWith<$Res> get workspace {

  return $WorkspaceStateCopyWith<$Res>(_self.workspace, (value) {
    return _then(_self.copyWith(workspace: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationActivationFailureCopyWith<$Res>? get activationFailure {
    if (_self.activationFailure == null) {
    return null;
  }

  return $ConversationActivationFailureCopyWith<$Res>(_self.activationFailure!, (value) {
    return _then(_self.copyWith(activationFailure: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryStateCopyWith<$Res> get projects {

  return $ProjectDirectoryStateCopyWith<$Res>(_self.projects, (value) {
    return _then(_self.copyWith(projects: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryStateCopyWith<$Res> get agents {

  return $AgentDirectoryStateCopyWith<$Res>(_self.agents, (value) {
    return _then(_self.copyWith(agents: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectRecordCopyWith<$Res>? get selectedProject {
    if (_self.selectedProject == null) {
    return null;
  }

  return $ProjectRecordCopyWith<$Res>(_self.selectedProject!, (value) {
    return _then(_self.copyWith(selectedProject: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get projectReadError {
    if (_self.projectReadError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.projectReadError!, (value) {
    return _then(_self.copyWith(projectReadError: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetadataStateCopyWith<$Res>? get selectedMetadata {
    if (_self.selectedMetadata == null) {
    return null;
  }

  return $ThreadMetadataStateCopyWith<$Res>(_self.selectedMetadata!, (value) {
    return _then(_self.copyWith(selectedMetadata: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get metadataDemandError {
    if (_self.metadataDemandError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.metadataDemandError!, (value) {
    return _then(_self.copyWith(metadataDemandError: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceOpenResultCopyWith<$Res>? get openResult {
    if (_self.openResult == null) {
    return null;
  }

  return $WorkspaceOpenResultCopyWith<$Res>(_self.openResult!, (value) {
    return _then(_self.copyWith(openResult: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get openAdmissionError {
    if (_self.openAdmissionError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.openAdmissionError!, (value) {
    return _then(_self.copyWith(openAdmissionError: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceNavigationIntentCopyWith<$Res>? get navigation {
    if (_self.navigation == null) {
    return null;
  }

  return $WorkspaceNavigationIntentCopyWith<$Res>(_self.navigation!, (value) {
    return _then(_self.copyWith(navigation: value));
  });
}/// Create a copy of WorkspaceViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceNameEditorCopyWith<$Res>? get nameEditor {
    if (_self.nameEditor == null) {
    return null;
  }

  return $WorkspaceNameEditorCopyWith<$Res>(_self.nameEditor!, (value) {
    return _then(_self.copyWith(nameEditor: value));
  });
}
}

// dart format on
