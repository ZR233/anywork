// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sidebar_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SidebarProjectPage {

 int get generation; DirectoryQuery get query; ThreadDirectoryState? get directory; StudioFailure? get demandError;
/// Create a copy of SidebarProjectPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SidebarProjectPageCopyWith<SidebarProjectPage> get copyWith => _$SidebarProjectPageCopyWithImpl<SidebarProjectPage>(this as SidebarProjectPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SidebarProjectPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SidebarProjectPage&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.query, _this.query) || other.query == _this.query)&&(identical(other.directory, _this.directory) || other.directory == _this.directory)&&(identical(other.demandError, _this.demandError) || other.demandError == _this.demandError));
}


@override
int get hashCode {
  final _this = this as SidebarProjectPage;
  return Object.hash(runtimeType,_this.generation,_this.query,_this.directory,_this.demandError);
}



}

/// @nodoc
abstract mixin class $SidebarProjectPageCopyWith<$Res>  {
  factory $SidebarProjectPageCopyWith(SidebarProjectPage value, $Res Function(SidebarProjectPage) _then) = _$SidebarProjectPageCopyWithImpl;
@useResult
$Res call({
 int generation, DirectoryQuery query, ThreadDirectoryState? directory, StudioFailure? demandError
});


$DirectoryQueryCopyWith<$Res> get query;$ThreadDirectoryStateCopyWith<$Res>? get directory;$StudioFailureCopyWith<$Res>? get demandError;

}
/// @nodoc
class _$SidebarProjectPageCopyWithImpl<$Res>
    implements $SidebarProjectPageCopyWith<$Res> {
  _$SidebarProjectPageCopyWithImpl(this._self, this._then);

  final SidebarProjectPage _self;
  final $Res Function(SidebarProjectPage) _then;

/// Create a copy of SidebarProjectPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? generation = null,Object? query = null,Object? directory = freezed,Object? demandError = freezed,}) {
  return _then(SidebarProjectPage(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as DirectoryQuery,directory: freezed == directory ? _self.directory : directory // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryState?,demandError: freezed == demandError ? _self.demandError : demandError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of SidebarProjectPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DirectoryQueryCopyWith<$Res> get query {

  return $DirectoryQueryCopyWith<$Res>(_self.query, (value) {
    return _then(_self.copyWith(query: value));
  });
}/// Create a copy of SidebarProjectPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryStateCopyWith<$Res>? get directory {
    if (_self.directory == null) {
    return null;
  }

  return $ThreadDirectoryStateCopyWith<$Res>(_self.directory!, (value) {
    return _then(_self.copyWith(directory: value));
  });
}/// Create a copy of SidebarProjectPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get demandError {
    if (_self.demandError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.demandError!, (value) {
    return _then(_self.copyWith(demandError: value));
  });
}
}


/// Adds pattern-matching-related methods to [SidebarProjectPage].
extension SidebarProjectPagePatterns on SidebarProjectPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SidebarProjectPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SidebarProjectPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SidebarProjectPage value)  $default,){
final _that = this;
switch (_that) {
case _SidebarProjectPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SidebarProjectPage value)?  $default,){
final _that = this;
switch (_that) {
case _SidebarProjectPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int generation,  DirectoryQuery query,  ThreadDirectoryState? directory,  StudioFailure? demandError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SidebarProjectPage() when $default != null:
return $default(_that.generation,_that.query,_that.directory,_that.demandError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int generation,  DirectoryQuery query,  ThreadDirectoryState? directory,  StudioFailure? demandError)  $default,) {final _that = this;
switch (_that) {
case _SidebarProjectPage():
return $default(_that.generation,_that.query,_that.directory,_that.demandError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int generation,  DirectoryQuery query,  ThreadDirectoryState? directory,  StudioFailure? demandError)?  $default,) {final _that = this;
switch (_that) {
case _SidebarProjectPage() when $default != null:
return $default(_that.generation,_that.query,_that.directory,_that.demandError);case _:
  return null;

}
}

}

/// @nodoc


class _SidebarProjectPage implements SidebarProjectPage {
  const _SidebarProjectPage({required this.generation, required this.query, required this.directory, required this.demandError});


@override final  int generation;
@override final  DirectoryQuery query;
@override final  ThreadDirectoryState? directory;
@override final  StudioFailure? demandError;

/// Create a copy of SidebarProjectPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SidebarProjectPageCopyWith<_SidebarProjectPage> get copyWith => __$SidebarProjectPageCopyWithImpl<_SidebarProjectPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SidebarProjectPage&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.query, query) || other.query == query)&&(identical(other.directory, directory) || other.directory == directory)&&(identical(other.demandError, demandError) || other.demandError == demandError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,generation,query,directory,demandError);
}



}

/// @nodoc
abstract mixin class _$SidebarProjectPageCopyWith<$Res> implements $SidebarProjectPageCopyWith<$Res> {
  factory _$SidebarProjectPageCopyWith(_SidebarProjectPage value, $Res Function(_SidebarProjectPage) _then) = __$SidebarProjectPageCopyWithImpl;
@override @useResult
$Res call({
 int generation, DirectoryQuery query, ThreadDirectoryState? directory, StudioFailure? demandError
});


@override $DirectoryQueryCopyWith<$Res> get query;@override $ThreadDirectoryStateCopyWith<$Res>? get directory;@override $StudioFailureCopyWith<$Res>? get demandError;

}
/// @nodoc
class __$SidebarProjectPageCopyWithImpl<$Res>
    implements _$SidebarProjectPageCopyWith<$Res> {
  __$SidebarProjectPageCopyWithImpl(this._self, this._then);

  final _SidebarProjectPage _self;
  final $Res Function(_SidebarProjectPage) _then;

/// Create a copy of SidebarProjectPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? generation = null,Object? query = null,Object? directory = freezed,Object? demandError = freezed,}) {
  return _then(_SidebarProjectPage(
generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as DirectoryQuery,directory: freezed == directory ? _self.directory : directory // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryState?,demandError: freezed == demandError ? _self.demandError : demandError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of SidebarProjectPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DirectoryQueryCopyWith<$Res> get query {

  return $DirectoryQueryCopyWith<$Res>(_self.query, (value) {
    return _then(_self.copyWith(query: value));
  });
}/// Create a copy of SidebarProjectPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryStateCopyWith<$Res>? get directory {
    if (_self.directory == null) {
    return null;
  }

  return $ThreadDirectoryStateCopyWith<$Res>(_self.directory!, (value) {
    return _then(_self.copyWith(directory: value));
  });
}/// Create a copy of SidebarProjectPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get demandError {
    if (_self.demandError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.demandError!, (value) {
    return _then(_self.copyWith(demandError: value));
  });
}
}

/// @nodoc
mixin _$SidebarPreferenceWrite {

 int get intent; bool get pending; OperationState? get operation; StudioFailure? get admissionError; StudioFailure? get observationError;
/// Create a copy of SidebarPreferenceWrite
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SidebarPreferenceWriteCopyWith<SidebarPreferenceWrite> get copyWith => _$SidebarPreferenceWriteCopyWithImpl<SidebarPreferenceWrite>(this as SidebarPreferenceWrite, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SidebarPreferenceWrite;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SidebarPreferenceWrite&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.pending, _this.pending) || other.pending == _this.pending)&&(identical(other.operation, _this.operation) || other.operation == _this.operation)&&(identical(other.admissionError, _this.admissionError) || other.admissionError == _this.admissionError)&&(identical(other.observationError, _this.observationError) || other.observationError == _this.observationError));
}


@override
int get hashCode {
  final _this = this as SidebarPreferenceWrite;
  return Object.hash(runtimeType,_this.intent,_this.pending,_this.operation,_this.admissionError,_this.observationError);
}



}

/// @nodoc
abstract mixin class $SidebarPreferenceWriteCopyWith<$Res>  {
  factory $SidebarPreferenceWriteCopyWith(SidebarPreferenceWrite value, $Res Function(SidebarPreferenceWrite) _then) = _$SidebarPreferenceWriteCopyWithImpl;
@useResult
$Res call({
 int intent, bool pending, OperationState? operation, StudioFailure? admissionError, StudioFailure? observationError
});


$OperationStateCopyWith<$Res>? get operation;$StudioFailureCopyWith<$Res>? get admissionError;$StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class _$SidebarPreferenceWriteCopyWithImpl<$Res>
    implements $SidebarPreferenceWriteCopyWith<$Res> {
  _$SidebarPreferenceWriteCopyWithImpl(this._self, this._then);

  final SidebarPreferenceWrite _self;
  final $Res Function(SidebarPreferenceWrite) _then;

/// Create a copy of SidebarPreferenceWrite
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,Object? pending = null,Object? operation = freezed,Object? admissionError = freezed,Object? observationError = freezed,}) {
  return _then(SidebarPreferenceWrite(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,admissionError: freezed == admissionError ? _self.admissionError : admissionError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of SidebarPreferenceWrite
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
}/// Create a copy of SidebarPreferenceWrite
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
}/// Create a copy of SidebarPreferenceWrite
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


/// Adds pattern-matching-related methods to [SidebarPreferenceWrite].
extension SidebarPreferenceWritePatterns on SidebarPreferenceWrite {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SidebarPreferenceWrite value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SidebarPreferenceWrite() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SidebarPreferenceWrite value)  $default,){
final _that = this;
switch (_that) {
case _SidebarPreferenceWrite():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SidebarPreferenceWrite value)?  $default,){
final _that = this;
switch (_that) {
case _SidebarPreferenceWrite() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int intent,  bool pending,  OperationState? operation,  StudioFailure? admissionError,  StudioFailure? observationError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SidebarPreferenceWrite() when $default != null:
return $default(_that.intent,_that.pending,_that.operation,_that.admissionError,_that.observationError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int intent,  bool pending,  OperationState? operation,  StudioFailure? admissionError,  StudioFailure? observationError)  $default,) {final _that = this;
switch (_that) {
case _SidebarPreferenceWrite():
return $default(_that.intent,_that.pending,_that.operation,_that.admissionError,_that.observationError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int intent,  bool pending,  OperationState? operation,  StudioFailure? admissionError,  StudioFailure? observationError)?  $default,) {final _that = this;
switch (_that) {
case _SidebarPreferenceWrite() when $default != null:
return $default(_that.intent,_that.pending,_that.operation,_that.admissionError,_that.observationError);case _:
  return null;

}
}

}

/// @nodoc


class _SidebarPreferenceWrite implements SidebarPreferenceWrite {
  const _SidebarPreferenceWrite({required this.intent, required this.pending, required this.operation, required this.admissionError, this.observationError});


@override final  int intent;
@override final  bool pending;
@override final  OperationState? operation;
@override final  StudioFailure? admissionError;
@override final  StudioFailure? observationError;

/// Create a copy of SidebarPreferenceWrite
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SidebarPreferenceWriteCopyWith<_SidebarPreferenceWrite> get copyWith => __$SidebarPreferenceWriteCopyWithImpl<_SidebarPreferenceWrite>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SidebarPreferenceWrite&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.admissionError, admissionError) || other.admissionError == admissionError)&&(identical(other.observationError, observationError) || other.observationError == observationError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,pending,operation,admissionError,observationError);
}



}

/// @nodoc
abstract mixin class _$SidebarPreferenceWriteCopyWith<$Res> implements $SidebarPreferenceWriteCopyWith<$Res> {
  factory _$SidebarPreferenceWriteCopyWith(_SidebarPreferenceWrite value, $Res Function(_SidebarPreferenceWrite) _then) = __$SidebarPreferenceWriteCopyWithImpl;
@override @useResult
$Res call({
 int intent, bool pending, OperationState? operation, StudioFailure? admissionError, StudioFailure? observationError
});


@override $OperationStateCopyWith<$Res>? get operation;@override $StudioFailureCopyWith<$Res>? get admissionError;@override $StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class __$SidebarPreferenceWriteCopyWithImpl<$Res>
    implements _$SidebarPreferenceWriteCopyWith<$Res> {
  __$SidebarPreferenceWriteCopyWithImpl(this._self, this._then);

  final _SidebarPreferenceWrite _self;
  final $Res Function(_SidebarPreferenceWrite) _then;

/// Create a copy of SidebarPreferenceWrite
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? pending = null,Object? operation = freezed,Object? admissionError = freezed,Object? observationError = freezed,}) {
  return _then(_SidebarPreferenceWrite(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,admissionError: freezed == admissionError ? _self.admissionError : admissionError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of SidebarPreferenceWrite
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
}/// Create a copy of SidebarPreferenceWrite
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
}/// Create a copy of SidebarPreferenceWrite
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
mixin _$SidebarViewState {

 WorkspaceState get workspace; ProjectDirectoryState get projects; ConfigurationState get configuration; UpdatesBrief? get updatesBrief; String get rawQuery; String get normalizedQuery; DirectoryFilter get filter; bool get archived; Set<String> get expandedProjectIds; int get queryGeneration; Map<String, SidebarProjectPage> get pages; double? get widthDraft; int get widthIntent; Map<String, SidebarPreferenceWrite> get writes; StudioFailure? get preferencesReadError; StudioFailure? get projectsReadError; StudioFailure? get projectSourceReadError; bool get sealed;
/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SidebarViewStateCopyWith<SidebarViewState> get copyWith => _$SidebarViewStateCopyWithImpl<SidebarViewState>(this as SidebarViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SidebarViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SidebarViewState&&(identical(other.workspace, _this.workspace) || other.workspace == _this.workspace)&&(identical(other.projects, _this.projects) || other.projects == _this.projects)&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.updatesBrief, _this.updatesBrief) || other.updatesBrief == _this.updatesBrief)&&(identical(other.rawQuery, _this.rawQuery) || other.rawQuery == _this.rawQuery)&&(identical(other.normalizedQuery, _this.normalizedQuery) || other.normalizedQuery == _this.normalizedQuery)&&(identical(other.filter, _this.filter) || other.filter == _this.filter)&&(identical(other.archived, _this.archived) || other.archived == _this.archived)&&const DeepCollectionEquality().equals(other.expandedProjectIds, _this.expandedProjectIds)&&(identical(other.queryGeneration, _this.queryGeneration) || other.queryGeneration == _this.queryGeneration)&&const DeepCollectionEquality().equals(other.pages, _this.pages)&&(identical(other.widthDraft, _this.widthDraft) || other.widthDraft == _this.widthDraft)&&(identical(other.widthIntent, _this.widthIntent) || other.widthIntent == _this.widthIntent)&&const DeepCollectionEquality().equals(other.writes, _this.writes)&&(identical(other.preferencesReadError, _this.preferencesReadError) || other.preferencesReadError == _this.preferencesReadError)&&(identical(other.projectsReadError, _this.projectsReadError) || other.projectsReadError == _this.projectsReadError)&&(identical(other.projectSourceReadError, _this.projectSourceReadError) || other.projectSourceReadError == _this.projectSourceReadError)&&(identical(other.sealed, _this.sealed) || other.sealed == _this.sealed));
}


@override
int get hashCode {
  final _this = this as SidebarViewState;
  return Object.hash(runtimeType,_this.workspace,_this.projects,_this.configuration,_this.updatesBrief,_this.rawQuery,_this.normalizedQuery,_this.filter,_this.archived,const DeepCollectionEquality().hash(_this.expandedProjectIds),_this.queryGeneration,const DeepCollectionEquality().hash(_this.pages),_this.widthDraft,_this.widthIntent,const DeepCollectionEquality().hash(_this.writes),_this.preferencesReadError,_this.projectsReadError,_this.projectSourceReadError,_this.sealed);
}



}

/// @nodoc
abstract mixin class $SidebarViewStateCopyWith<$Res>  {
  factory $SidebarViewStateCopyWith(SidebarViewState value, $Res Function(SidebarViewState) _then) = _$SidebarViewStateCopyWithImpl;
@useResult
$Res call({
 WorkspaceState workspace, ProjectDirectoryState projects, ConfigurationState configuration, UpdatesBrief? updatesBrief, String rawQuery, String normalizedQuery, DirectoryFilter filter, bool archived, Set<String> expandedProjectIds, int queryGeneration, Map<String, SidebarProjectPage> pages, double? widthDraft, int widthIntent, Map<String, SidebarPreferenceWrite> writes, StudioFailure? preferencesReadError, StudioFailure? projectsReadError, StudioFailure? projectSourceReadError, bool sealed
});


$WorkspaceStateCopyWith<$Res> get workspace;$ProjectDirectoryStateCopyWith<$Res> get projects;$ConfigurationStateCopyWith<$Res> get configuration;$UpdatesBriefCopyWith<$Res>? get updatesBrief;$StudioFailureCopyWith<$Res>? get preferencesReadError;$StudioFailureCopyWith<$Res>? get projectsReadError;$StudioFailureCopyWith<$Res>? get projectSourceReadError;

}
/// @nodoc
class _$SidebarViewStateCopyWithImpl<$Res>
    implements $SidebarViewStateCopyWith<$Res> {
  _$SidebarViewStateCopyWithImpl(this._self, this._then);

  final SidebarViewState _self;
  final $Res Function(SidebarViewState) _then;

/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? workspace = null,Object? projects = null,Object? configuration = null,Object? updatesBrief = freezed,Object? rawQuery = null,Object? normalizedQuery = null,Object? filter = null,Object? archived = null,Object? expandedProjectIds = null,Object? queryGeneration = null,Object? pages = null,Object? widthDraft = freezed,Object? widthIntent = null,Object? writes = null,Object? preferencesReadError = freezed,Object? projectsReadError = freezed,Object? projectSourceReadError = freezed,Object? sealed = null,}) {
  return _then(SidebarViewState(
workspace: null == workspace ? _self.workspace : workspace // ignore: cast_nullable_to_non_nullable
as WorkspaceState,projects: null == projects ? _self.projects : projects // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryState,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationState,updatesBrief: freezed == updatesBrief ? _self.updatesBrief : updatesBrief // ignore: cast_nullable_to_non_nullable
as UpdatesBrief?,rawQuery: null == rawQuery ? _self.rawQuery : rawQuery // ignore: cast_nullable_to_non_nullable
as String,normalizedQuery: null == normalizedQuery ? _self.normalizedQuery : normalizedQuery // ignore: cast_nullable_to_non_nullable
as String,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as DirectoryFilter,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as bool,expandedProjectIds: null == expandedProjectIds ? _self.expandedProjectIds : expandedProjectIds // ignore: cast_nullable_to_non_nullable
as Set<String>,queryGeneration: null == queryGeneration ? _self.queryGeneration : queryGeneration // ignore: cast_nullable_to_non_nullable
as int,pages: null == pages ? _self.pages : pages // ignore: cast_nullable_to_non_nullable
as Map<String, SidebarProjectPage>,widthDraft: freezed == widthDraft ? _self.widthDraft : widthDraft // ignore: cast_nullable_to_non_nullable
as double?,widthIntent: null == widthIntent ? _self.widthIntent : widthIntent // ignore: cast_nullable_to_non_nullable
as int,writes: null == writes ? _self.writes : writes // ignore: cast_nullable_to_non_nullable
as Map<String, SidebarPreferenceWrite>,preferencesReadError: freezed == preferencesReadError ? _self.preferencesReadError : preferencesReadError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,projectsReadError: freezed == projectsReadError ? _self.projectsReadError : projectsReadError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,projectSourceReadError: freezed == projectSourceReadError ? _self.projectSourceReadError : projectSourceReadError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,sealed: null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceStateCopyWith<$Res> get workspace {

  return $WorkspaceStateCopyWith<$Res>(_self.workspace, (value) {
    return _then(_self.copyWith(workspace: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryStateCopyWith<$Res> get projects {

  return $ProjectDirectoryStateCopyWith<$Res>(_self.projects, (value) {
    return _then(_self.copyWith(projects: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get configuration {

  return $ConfigurationStateCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesBriefCopyWith<$Res>? get updatesBrief {
    if (_self.updatesBrief == null) {
    return null;
  }

  return $UpdatesBriefCopyWith<$Res>(_self.updatesBrief!, (value) {
    return _then(_self.copyWith(updatesBrief: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get preferencesReadError {
    if (_self.preferencesReadError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.preferencesReadError!, (value) {
    return _then(_self.copyWith(preferencesReadError: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get projectsReadError {
    if (_self.projectsReadError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.projectsReadError!, (value) {
    return _then(_self.copyWith(projectsReadError: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get projectSourceReadError {
    if (_self.projectSourceReadError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.projectSourceReadError!, (value) {
    return _then(_self.copyWith(projectSourceReadError: value));
  });
}
}


/// Adds pattern-matching-related methods to [SidebarViewState].
extension SidebarViewStatePatterns on SidebarViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SidebarViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SidebarViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SidebarViewState value)  $default,){
final _that = this;
switch (_that) {
case _SidebarViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SidebarViewState value)?  $default,){
final _that = this;
switch (_that) {
case _SidebarViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WorkspaceState workspace,  ProjectDirectoryState projects,  ConfigurationState configuration,  UpdatesBrief? updatesBrief,  String rawQuery,  String normalizedQuery,  DirectoryFilter filter,  bool archived,  Set<String> expandedProjectIds,  int queryGeneration,  Map<String, SidebarProjectPage> pages,  double? widthDraft,  int widthIntent,  Map<String, SidebarPreferenceWrite> writes,  StudioFailure? preferencesReadError,  StudioFailure? projectsReadError,  StudioFailure? projectSourceReadError,  bool sealed)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SidebarViewState() when $default != null:
return $default(_that.workspace,_that.projects,_that.configuration,_that.updatesBrief,_that.rawQuery,_that.normalizedQuery,_that.filter,_that.archived,_that.expandedProjectIds,_that.queryGeneration,_that.pages,_that.widthDraft,_that.widthIntent,_that.writes,_that.preferencesReadError,_that.projectsReadError,_that.projectSourceReadError,_that.sealed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WorkspaceState workspace,  ProjectDirectoryState projects,  ConfigurationState configuration,  UpdatesBrief? updatesBrief,  String rawQuery,  String normalizedQuery,  DirectoryFilter filter,  bool archived,  Set<String> expandedProjectIds,  int queryGeneration,  Map<String, SidebarProjectPage> pages,  double? widthDraft,  int widthIntent,  Map<String, SidebarPreferenceWrite> writes,  StudioFailure? preferencesReadError,  StudioFailure? projectsReadError,  StudioFailure? projectSourceReadError,  bool sealed)  $default,) {final _that = this;
switch (_that) {
case _SidebarViewState():
return $default(_that.workspace,_that.projects,_that.configuration,_that.updatesBrief,_that.rawQuery,_that.normalizedQuery,_that.filter,_that.archived,_that.expandedProjectIds,_that.queryGeneration,_that.pages,_that.widthDraft,_that.widthIntent,_that.writes,_that.preferencesReadError,_that.projectsReadError,_that.projectSourceReadError,_that.sealed);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WorkspaceState workspace,  ProjectDirectoryState projects,  ConfigurationState configuration,  UpdatesBrief? updatesBrief,  String rawQuery,  String normalizedQuery,  DirectoryFilter filter,  bool archived,  Set<String> expandedProjectIds,  int queryGeneration,  Map<String, SidebarProjectPage> pages,  double? widthDraft,  int widthIntent,  Map<String, SidebarPreferenceWrite> writes,  StudioFailure? preferencesReadError,  StudioFailure? projectsReadError,  StudioFailure? projectSourceReadError,  bool sealed)?  $default,) {final _that = this;
switch (_that) {
case _SidebarViewState() when $default != null:
return $default(_that.workspace,_that.projects,_that.configuration,_that.updatesBrief,_that.rawQuery,_that.normalizedQuery,_that.filter,_that.archived,_that.expandedProjectIds,_that.queryGeneration,_that.pages,_that.widthDraft,_that.widthIntent,_that.writes,_that.preferencesReadError,_that.projectsReadError,_that.projectSourceReadError,_that.sealed);case _:
  return null;

}
}

}

/// @nodoc


class _SidebarViewState extends SidebarViewState {
  const _SidebarViewState({required this.workspace, required this.projects, required this.configuration, required this.updatesBrief, required this.rawQuery, required this.normalizedQuery, required this.filter, required this.archived, required  Set<String> expandedProjectIds, required this.queryGeneration, required  Map<String, SidebarProjectPage> pages, required this.widthDraft, required this.widthIntent, required  Map<String, SidebarPreferenceWrite> writes, required this.preferencesReadError, required this.projectsReadError, required this.projectSourceReadError, required this.sealed}): _expandedProjectIds = expandedProjectIds,_pages = pages,_writes = writes,super._();


@override final  WorkspaceState workspace;
@override final  ProjectDirectoryState projects;
@override final  ConfigurationState configuration;
@override final  UpdatesBrief? updatesBrief;
@override final  String rawQuery;
@override final  String normalizedQuery;
@override final  DirectoryFilter filter;
@override final  bool archived;
 final  Set<String> _expandedProjectIds;
@override Set<String> get expandedProjectIds {
  if (_expandedProjectIds is EqualUnmodifiableSetView) return _expandedProjectIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_expandedProjectIds);
}

@override final  int queryGeneration;
 final  Map<String, SidebarProjectPage> _pages;
@override Map<String, SidebarProjectPage> get pages {
  if (_pages is EqualUnmodifiableMapView) return _pages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_pages);
}

@override final  double? widthDraft;
@override final  int widthIntent;
 final  Map<String, SidebarPreferenceWrite> _writes;
@override Map<String, SidebarPreferenceWrite> get writes {
  if (_writes is EqualUnmodifiableMapView) return _writes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_writes);
}

@override final  StudioFailure? preferencesReadError;
@override final  StudioFailure? projectsReadError;
@override final  StudioFailure? projectSourceReadError;
@override final  bool sealed;

/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SidebarViewStateCopyWith<_SidebarViewState> get copyWith => __$SidebarViewStateCopyWithImpl<_SidebarViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SidebarViewState&&(identical(other.workspace, workspace) || other.workspace == workspace)&&(identical(other.projects, projects) || other.projects == projects)&&(identical(other.configuration, configuration) || other.configuration == configuration)&&(identical(other.updatesBrief, updatesBrief) || other.updatesBrief == updatesBrief)&&(identical(other.rawQuery, rawQuery) || other.rawQuery == rawQuery)&&(identical(other.normalizedQuery, normalizedQuery) || other.normalizedQuery == normalizedQuery)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.archived, archived) || other.archived == archived)&&const DeepCollectionEquality().equals(other.expandedProjectIds, _expandedProjectIds)&&(identical(other.queryGeneration, queryGeneration) || other.queryGeneration == queryGeneration)&&const DeepCollectionEquality().equals(other.pages, _pages)&&(identical(other.widthDraft, widthDraft) || other.widthDraft == widthDraft)&&(identical(other.widthIntent, widthIntent) || other.widthIntent == widthIntent)&&const DeepCollectionEquality().equals(other.writes, _writes)&&(identical(other.preferencesReadError, preferencesReadError) || other.preferencesReadError == preferencesReadError)&&(identical(other.projectsReadError, projectsReadError) || other.projectsReadError == projectsReadError)&&(identical(other.projectSourceReadError, projectSourceReadError) || other.projectSourceReadError == projectSourceReadError)&&(identical(other.sealed, sealed) || other.sealed == sealed));
}


@override
int get hashCode {
    return Object.hash(runtimeType,workspace,projects,configuration,updatesBrief,rawQuery,normalizedQuery,filter,archived,const DeepCollectionEquality().hash(_expandedProjectIds),queryGeneration,const DeepCollectionEquality().hash(_pages),widthDraft,widthIntent,const DeepCollectionEquality().hash(_writes),preferencesReadError,projectsReadError,projectSourceReadError,sealed);
}



}

/// @nodoc
abstract mixin class _$SidebarViewStateCopyWith<$Res> implements $SidebarViewStateCopyWith<$Res> {
  factory _$SidebarViewStateCopyWith(_SidebarViewState value, $Res Function(_SidebarViewState) _then) = __$SidebarViewStateCopyWithImpl;
@override @useResult
$Res call({
 WorkspaceState workspace, ProjectDirectoryState projects, ConfigurationState configuration, UpdatesBrief? updatesBrief, String rawQuery, String normalizedQuery, DirectoryFilter filter, bool archived, Set<String> expandedProjectIds, int queryGeneration, Map<String, SidebarProjectPage> pages, double? widthDraft, int widthIntent, Map<String, SidebarPreferenceWrite> writes, StudioFailure? preferencesReadError, StudioFailure? projectsReadError, StudioFailure? projectSourceReadError, bool sealed
});


@override $WorkspaceStateCopyWith<$Res> get workspace;@override $ProjectDirectoryStateCopyWith<$Res> get projects;@override $ConfigurationStateCopyWith<$Res> get configuration;@override $UpdatesBriefCopyWith<$Res>? get updatesBrief;@override $StudioFailureCopyWith<$Res>? get preferencesReadError;@override $StudioFailureCopyWith<$Res>? get projectsReadError;@override $StudioFailureCopyWith<$Res>? get projectSourceReadError;

}
/// @nodoc
class __$SidebarViewStateCopyWithImpl<$Res>
    implements _$SidebarViewStateCopyWith<$Res> {
  __$SidebarViewStateCopyWithImpl(this._self, this._then);

  final _SidebarViewState _self;
  final $Res Function(_SidebarViewState) _then;

/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? workspace = null,Object? projects = null,Object? configuration = null,Object? updatesBrief = freezed,Object? rawQuery = null,Object? normalizedQuery = null,Object? filter = null,Object? archived = null,Object? expandedProjectIds = null,Object? queryGeneration = null,Object? pages = null,Object? widthDraft = freezed,Object? widthIntent = null,Object? writes = null,Object? preferencesReadError = freezed,Object? projectsReadError = freezed,Object? projectSourceReadError = freezed,Object? sealed = null,}) {
  return _then(_SidebarViewState(
workspace: null == workspace ? _self.workspace : workspace // ignore: cast_nullable_to_non_nullable
as WorkspaceState,projects: null == projects ? _self.projects : projects // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryState,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationState,updatesBrief: freezed == updatesBrief ? _self.updatesBrief : updatesBrief // ignore: cast_nullable_to_non_nullable
as UpdatesBrief?,rawQuery: null == rawQuery ? _self.rawQuery : rawQuery // ignore: cast_nullable_to_non_nullable
as String,normalizedQuery: null == normalizedQuery ? _self.normalizedQuery : normalizedQuery // ignore: cast_nullable_to_non_nullable
as String,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as DirectoryFilter,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as bool,expandedProjectIds: null == expandedProjectIds ? _self._expandedProjectIds : expandedProjectIds // ignore: cast_nullable_to_non_nullable
as Set<String>,queryGeneration: null == queryGeneration ? _self.queryGeneration : queryGeneration // ignore: cast_nullable_to_non_nullable
as int,pages: null == pages ? _self._pages : pages // ignore: cast_nullable_to_non_nullable
as Map<String, SidebarProjectPage>,widthDraft: freezed == widthDraft ? _self.widthDraft : widthDraft // ignore: cast_nullable_to_non_nullable
as double?,widthIntent: null == widthIntent ? _self.widthIntent : widthIntent // ignore: cast_nullable_to_non_nullable
as int,writes: null == writes ? _self._writes : writes // ignore: cast_nullable_to_non_nullable
as Map<String, SidebarPreferenceWrite>,preferencesReadError: freezed == preferencesReadError ? _self.preferencesReadError : preferencesReadError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,projectsReadError: freezed == projectsReadError ? _self.projectsReadError : projectsReadError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,projectSourceReadError: freezed == projectSourceReadError ? _self.projectSourceReadError : projectSourceReadError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,sealed: null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceStateCopyWith<$Res> get workspace {

  return $WorkspaceStateCopyWith<$Res>(_self.workspace, (value) {
    return _then(_self.copyWith(workspace: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryStateCopyWith<$Res> get projects {

  return $ProjectDirectoryStateCopyWith<$Res>(_self.projects, (value) {
    return _then(_self.copyWith(projects: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get configuration {

  return $ConfigurationStateCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesBriefCopyWith<$Res>? get updatesBrief {
    if (_self.updatesBrief == null) {
    return null;
  }

  return $UpdatesBriefCopyWith<$Res>(_self.updatesBrief!, (value) {
    return _then(_self.copyWith(updatesBrief: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get preferencesReadError {
    if (_self.preferencesReadError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.preferencesReadError!, (value) {
    return _then(_self.copyWith(preferencesReadError: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get projectsReadError {
    if (_self.projectsReadError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.projectsReadError!, (value) {
    return _then(_self.copyWith(projectsReadError: value));
  });
}/// Create a copy of SidebarViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get projectSourceReadError {
    if (_self.projectSourceReadError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.projectSourceReadError!, (value) {
    return _then(_self.copyWith(projectSourceReadError: value));
  });
}
}

// dart format on
