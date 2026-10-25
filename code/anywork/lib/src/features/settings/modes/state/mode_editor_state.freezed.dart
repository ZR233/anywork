// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mode_editor_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModeEditorSelection {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeEditorSelection);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModeEditorSelection()';
}


}

/// @nodoc
class $ModeEditorSelectionCopyWith<$Res>  {
$ModeEditorSelectionCopyWith(ModeEditorSelection _, $Res Function(ModeEditorSelection) __);
}


/// Adds pattern-matching-related methods to [ModeEditorSelection].
extension ModeEditorSelectionPatterns on ModeEditorSelection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NoModeSelection value)?  none,TResult Function( ModeNodeSelection value)?  node,TResult Function( ModeEdgeSelection value)?  edge,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NoModeSelection() when none != null:
return none(_that);case ModeNodeSelection() when node != null:
return node(_that);case ModeEdgeSelection() when edge != null:
return edge(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NoModeSelection value)  none,required TResult Function( ModeNodeSelection value)  node,required TResult Function( ModeEdgeSelection value)  edge,}){
final _that = this;
switch (_that) {
case NoModeSelection():
return none(_that);case ModeNodeSelection():
return node(_that);case ModeEdgeSelection():
return edge(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NoModeSelection value)?  none,TResult? Function( ModeNodeSelection value)?  node,TResult? Function( ModeEdgeSelection value)?  edge,}){
final _that = this;
switch (_that) {
case NoModeSelection() when none != null:
return none(_that);case ModeNodeSelection() when node != null:
return node(_that);case ModeEdgeSelection() when edge != null:
return edge(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  none,TResult Function( String stateId)?  node,TResult Function( String sourceStateId,  String targetStateId)?  edge,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NoModeSelection() when none != null:
return none();case ModeNodeSelection() when node != null:
return node(_that.stateId);case ModeEdgeSelection() when edge != null:
return edge(_that.sourceStateId,_that.targetStateId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  none,required TResult Function( String stateId)  node,required TResult Function( String sourceStateId,  String targetStateId)  edge,}) {final _that = this;
switch (_that) {
case NoModeSelection():
return none();case ModeNodeSelection():
return node(_that.stateId);case ModeEdgeSelection():
return edge(_that.sourceStateId,_that.targetStateId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  none,TResult? Function( String stateId)?  node,TResult? Function( String sourceStateId,  String targetStateId)?  edge,}) {final _that = this;
switch (_that) {
case NoModeSelection() when none != null:
return none();case ModeNodeSelection() when node != null:
return node(_that.stateId);case ModeEdgeSelection() when edge != null:
return edge(_that.sourceStateId,_that.targetStateId);case _:
  return null;

}
}

}

/// @nodoc


class NoModeSelection implements ModeEditorSelection {
  const NoModeSelection();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NoModeSelection);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ModeEditorSelection.none()';
}


}




/// @nodoc


class ModeNodeSelection implements ModeEditorSelection {
  const ModeNodeSelection({required this.stateId});


 final  String stateId;

/// Create a copy of ModeEditorSelection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeNodeSelectionCopyWith<ModeNodeSelection> get copyWith => _$ModeNodeSelectionCopyWithImpl<ModeNodeSelection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeNodeSelection&&(identical(other.stateId, stateId) || other.stateId == stateId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stateId);
}

@override
String toString() {
    return 'ModeEditorSelection.node(stateId: $stateId)';
}


}

/// @nodoc
abstract mixin class $ModeNodeSelectionCopyWith<$Res> implements $ModeEditorSelectionCopyWith<$Res> {
  factory $ModeNodeSelectionCopyWith(ModeNodeSelection value, $Res Function(ModeNodeSelection) _then) = _$ModeNodeSelectionCopyWithImpl;
@useResult
$Res call({
 String stateId
});




}
/// @nodoc
class _$ModeNodeSelectionCopyWithImpl<$Res>
    implements $ModeNodeSelectionCopyWith<$Res> {
  _$ModeNodeSelectionCopyWithImpl(this._self, this._then);

  final ModeNodeSelection _self;
  final $Res Function(ModeNodeSelection) _then;

/// Create a copy of ModeEditorSelection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? stateId = null,}) {
  return _then(ModeNodeSelection(
stateId: null == stateId ? _self.stateId : stateId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ModeEdgeSelection implements ModeEditorSelection {
  const ModeEdgeSelection({required this.sourceStateId, required this.targetStateId});


 final  String sourceStateId;
 final  String targetStateId;

/// Create a copy of ModeEditorSelection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeEdgeSelectionCopyWith<ModeEdgeSelection> get copyWith => _$ModeEdgeSelectionCopyWithImpl<ModeEdgeSelection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeEdgeSelection&&(identical(other.sourceStateId, sourceStateId) || other.sourceStateId == sourceStateId)&&(identical(other.targetStateId, targetStateId) || other.targetStateId == targetStateId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sourceStateId,targetStateId);
}

@override
String toString() {
    return 'ModeEditorSelection.edge(sourceStateId: $sourceStateId, targetStateId: $targetStateId)';
}


}

/// @nodoc
abstract mixin class $ModeEdgeSelectionCopyWith<$Res> implements $ModeEditorSelectionCopyWith<$Res> {
  factory $ModeEdgeSelectionCopyWith(ModeEdgeSelection value, $Res Function(ModeEdgeSelection) _then) = _$ModeEdgeSelectionCopyWithImpl;
@useResult
$Res call({
 String sourceStateId, String targetStateId
});




}
/// @nodoc
class _$ModeEdgeSelectionCopyWithImpl<$Res>
    implements $ModeEdgeSelectionCopyWith<$Res> {
  _$ModeEdgeSelectionCopyWithImpl(this._self, this._then);

  final ModeEdgeSelection _self;
  final $Res Function(ModeEdgeSelection) _then;

/// Create a copy of ModeEditorSelection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sourceStateId = null,Object? targetStateId = null,}) {
  return _then(ModeEdgeSelection(
sourceStateId: null == sourceStateId ? _self.sourceStateId : sourceStateId // ignore: cast_nullable_to_non_nullable
as String,targetStateId: null == targetStateId ? _self.targetStateId : targetStateId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ModeEditorSnapshot {

 ModeDocument get document; String get jsonText; bool get jsonApplied; String get orderText; ValidationIssue? get orderError; Map<String, String> get criteriaRaw;
/// Create a copy of ModeEditorSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeEditorSnapshotCopyWith<ModeEditorSnapshot> get copyWith => _$ModeEditorSnapshotCopyWithImpl<ModeEditorSnapshot>(this as ModeEditorSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeEditorSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeEditorSnapshot&&(identical(other.document, _this.document) || other.document == _this.document)&&(identical(other.jsonText, _this.jsonText) || other.jsonText == _this.jsonText)&&(identical(other.jsonApplied, _this.jsonApplied) || other.jsonApplied == _this.jsonApplied)&&(identical(other.orderText, _this.orderText) || other.orderText == _this.orderText)&&(identical(other.orderError, _this.orderError) || other.orderError == _this.orderError)&&const DeepCollectionEquality().equals(other.criteriaRaw, _this.criteriaRaw));
}


@override
int get hashCode {
  final _this = this as ModeEditorSnapshot;
  return Object.hash(runtimeType,_this.document,_this.jsonText,_this.jsonApplied,_this.orderText,_this.orderError,const DeepCollectionEquality().hash(_this.criteriaRaw));
}



}

/// @nodoc
abstract mixin class $ModeEditorSnapshotCopyWith<$Res>  {
  factory $ModeEditorSnapshotCopyWith(ModeEditorSnapshot value, $Res Function(ModeEditorSnapshot) _then) = _$ModeEditorSnapshotCopyWithImpl;
@useResult
$Res call({
 ModeDocument document, String jsonText, bool jsonApplied, String orderText, ValidationIssue? orderError, Map<String, String> criteriaRaw
});


$ModeDocumentCopyWith<$Res> get document;$ValidationIssueCopyWith<$Res>? get orderError;

}
/// @nodoc
class _$ModeEditorSnapshotCopyWithImpl<$Res>
    implements $ModeEditorSnapshotCopyWith<$Res> {
  _$ModeEditorSnapshotCopyWithImpl(this._self, this._then);

  final ModeEditorSnapshot _self;
  final $Res Function(ModeEditorSnapshot) _then;

/// Create a copy of ModeEditorSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? document = null,Object? jsonText = null,Object? jsonApplied = null,Object? orderText = null,Object? orderError = freezed,Object? criteriaRaw = null,}) {
  return _then(ModeEditorSnapshot(
document: null == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as ModeDocument,jsonText: null == jsonText ? _self.jsonText : jsonText // ignore: cast_nullable_to_non_nullable
as String,jsonApplied: null == jsonApplied ? _self.jsonApplied : jsonApplied // ignore: cast_nullable_to_non_nullable
as bool,orderText: null == orderText ? _self.orderText : orderText // ignore: cast_nullable_to_non_nullable
as String,orderError: freezed == orderError ? _self.orderError : orderError // ignore: cast_nullable_to_non_nullable
as ValidationIssue?,criteriaRaw: null == criteriaRaw ? _self.criteriaRaw : criteriaRaw // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}
/// Create a copy of ModeEditorSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDocumentCopyWith<$Res> get document {

  return $ModeDocumentCopyWith<$Res>(_self.document, (value) {
    return _then(_self.copyWith(document: value));
  });
}/// Create a copy of ModeEditorSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ValidationIssueCopyWith<$Res>? get orderError {
    if (_self.orderError == null) {
    return null;
  }

  return $ValidationIssueCopyWith<$Res>(_self.orderError!, (value) {
    return _then(_self.copyWith(orderError: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeEditorSnapshot].
extension ModeEditorSnapshotPatterns on ModeEditorSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeEditorSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeEditorSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeEditorSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _ModeEditorSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeEditorSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _ModeEditorSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModeDocument document,  String jsonText,  bool jsonApplied,  String orderText,  ValidationIssue? orderError,  Map<String, String> criteriaRaw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeEditorSnapshot() when $default != null:
return $default(_that.document,_that.jsonText,_that.jsonApplied,_that.orderText,_that.orderError,_that.criteriaRaw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModeDocument document,  String jsonText,  bool jsonApplied,  String orderText,  ValidationIssue? orderError,  Map<String, String> criteriaRaw)  $default,) {final _that = this;
switch (_that) {
case _ModeEditorSnapshot():
return $default(_that.document,_that.jsonText,_that.jsonApplied,_that.orderText,_that.orderError,_that.criteriaRaw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModeDocument document,  String jsonText,  bool jsonApplied,  String orderText,  ValidationIssue? orderError,  Map<String, String> criteriaRaw)?  $default,) {final _that = this;
switch (_that) {
case _ModeEditorSnapshot() when $default != null:
return $default(_that.document,_that.jsonText,_that.jsonApplied,_that.orderText,_that.orderError,_that.criteriaRaw);case _:
  return null;

}
}

}

/// @nodoc


class _ModeEditorSnapshot implements ModeEditorSnapshot {
  const _ModeEditorSnapshot({required this.document, required this.jsonText, required this.jsonApplied, required this.orderText, this.orderError,  Map<String, String> criteriaRaw = const {}}): _criteriaRaw = criteriaRaw;


@override final  ModeDocument document;
@override final  String jsonText;
@override final  bool jsonApplied;
@override final  String orderText;
@override final  ValidationIssue? orderError;
 final  Map<String, String> _criteriaRaw;
@override@JsonKey() Map<String, String> get criteriaRaw {
  if (_criteriaRaw is EqualUnmodifiableMapView) return _criteriaRaw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_criteriaRaw);
}


/// Create a copy of ModeEditorSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeEditorSnapshotCopyWith<_ModeEditorSnapshot> get copyWith => __$ModeEditorSnapshotCopyWithImpl<_ModeEditorSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeEditorSnapshot&&(identical(other.document, document) || other.document == document)&&(identical(other.jsonText, jsonText) || other.jsonText == jsonText)&&(identical(other.jsonApplied, jsonApplied) || other.jsonApplied == jsonApplied)&&(identical(other.orderText, orderText) || other.orderText == orderText)&&(identical(other.orderError, orderError) || other.orderError == orderError)&&const DeepCollectionEquality().equals(other.criteriaRaw, _criteriaRaw));
}


@override
int get hashCode {
    return Object.hash(runtimeType,document,jsonText,jsonApplied,orderText,orderError,const DeepCollectionEquality().hash(_criteriaRaw));
}



}

/// @nodoc
abstract mixin class _$ModeEditorSnapshotCopyWith<$Res> implements $ModeEditorSnapshotCopyWith<$Res> {
  factory _$ModeEditorSnapshotCopyWith(_ModeEditorSnapshot value, $Res Function(_ModeEditorSnapshot) _then) = __$ModeEditorSnapshotCopyWithImpl;
@override @useResult
$Res call({
 ModeDocument document, String jsonText, bool jsonApplied, String orderText, ValidationIssue? orderError, Map<String, String> criteriaRaw
});


@override $ModeDocumentCopyWith<$Res> get document;@override $ValidationIssueCopyWith<$Res>? get orderError;

}
/// @nodoc
class __$ModeEditorSnapshotCopyWithImpl<$Res>
    implements _$ModeEditorSnapshotCopyWith<$Res> {
  __$ModeEditorSnapshotCopyWithImpl(this._self, this._then);

  final _ModeEditorSnapshot _self;
  final $Res Function(_ModeEditorSnapshot) _then;

/// Create a copy of ModeEditorSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? document = null,Object? jsonText = null,Object? jsonApplied = null,Object? orderText = null,Object? orderError = freezed,Object? criteriaRaw = null,}) {
  return _then(_ModeEditorSnapshot(
document: null == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as ModeDocument,jsonText: null == jsonText ? _self.jsonText : jsonText // ignore: cast_nullable_to_non_nullable
as String,jsonApplied: null == jsonApplied ? _self.jsonApplied : jsonApplied // ignore: cast_nullable_to_non_nullable
as bool,orderText: null == orderText ? _self.orderText : orderText // ignore: cast_nullable_to_non_nullable
as String,orderError: freezed == orderError ? _self.orderError : orderError // ignore: cast_nullable_to_non_nullable
as ValidationIssue?,criteriaRaw: null == criteriaRaw ? _self._criteriaRaw : criteriaRaw // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

/// Create a copy of ModeEditorSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDocumentCopyWith<$Res> get document {

  return $ModeDocumentCopyWith<$Res>(_self.document, (value) {
    return _then(_self.copyWith(document: value));
  });
}/// Create a copy of ModeEditorSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ValidationIssueCopyWith<$Res>? get orderError {
    if (_self.orderError == null) {
    return null;
  }

  return $ValidationIssueCopyWith<$Res>(_self.orderError!, (value) {
    return _then(_self.copyWith(orderError: value));
  });
}
}

/// @nodoc
mixin _$ModeEditorViewState {

 ModesState get catalog; String? get selectedModeId; int? get catalogRevision; int? get draftCatalogRevision; ProductReadOrigin? get draftOrigin; ModeDocument? get document; String get jsonText; bool get jsonApplied; String get orderText; ValidationIssue? get orderError; Map<String, String> get criteriaRaw; ModeDocument? get savedDocument; String get savedJson; int? get savedRevision; bool get dirty; bool get readOnly; bool get busy; ModeEditorRequest? get request; List<ModeEditorSnapshot> get undo; List<ModeEditorSnapshot> get redo; ModeEditorTab get tab; ModeEditorSelection get selection; bool get inspectorOpen; String get query; bool get validationRequested; List<ValidationIssue> get issues; WorkflowPreviewSnapshot? get preview; String get previewReason; int get latestIntent; int get editRevision; SettingsAction? get operation; StudioFailure? get error; StudioFailure? get catalogReadError; ModeEditorNotice? get notice; ModeDialogDraft? get dialog;
/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeEditorViewStateCopyWith<ModeEditorViewState> get copyWith => _$ModeEditorViewStateCopyWithImpl<ModeEditorViewState>(this as ModeEditorViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeEditorViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeEditorViewState&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog)&&(identical(other.selectedModeId, _this.selectedModeId) || other.selectedModeId == _this.selectedModeId)&&(identical(other.catalogRevision, _this.catalogRevision) || other.catalogRevision == _this.catalogRevision)&&(identical(other.draftCatalogRevision, _this.draftCatalogRevision) || other.draftCatalogRevision == _this.draftCatalogRevision)&&(identical(other.draftOrigin, _this.draftOrigin) || other.draftOrigin == _this.draftOrigin)&&(identical(other.document, _this.document) || other.document == _this.document)&&(identical(other.jsonText, _this.jsonText) || other.jsonText == _this.jsonText)&&(identical(other.jsonApplied, _this.jsonApplied) || other.jsonApplied == _this.jsonApplied)&&(identical(other.orderText, _this.orderText) || other.orderText == _this.orderText)&&(identical(other.orderError, _this.orderError) || other.orderError == _this.orderError)&&const DeepCollectionEquality().equals(other.criteriaRaw, _this.criteriaRaw)&&(identical(other.savedDocument, _this.savedDocument) || other.savedDocument == _this.savedDocument)&&(identical(other.savedJson, _this.savedJson) || other.savedJson == _this.savedJson)&&(identical(other.savedRevision, _this.savedRevision) || other.savedRevision == _this.savedRevision)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&(identical(other.readOnly, _this.readOnly) || other.readOnly == _this.readOnly)&&(identical(other.busy, _this.busy) || other.busy == _this.busy)&&(identical(other.request, _this.request) || other.request == _this.request)&&const DeepCollectionEquality().equals(other.undo, _this.undo)&&const DeepCollectionEquality().equals(other.redo, _this.redo)&&(identical(other.tab, _this.tab) || other.tab == _this.tab)&&(identical(other.selection, _this.selection) || other.selection == _this.selection)&&(identical(other.inspectorOpen, _this.inspectorOpen) || other.inspectorOpen == _this.inspectorOpen)&&(identical(other.query, _this.query) || other.query == _this.query)&&(identical(other.validationRequested, _this.validationRequested) || other.validationRequested == _this.validationRequested)&&const DeepCollectionEquality().equals(other.issues, _this.issues)&&(identical(other.preview, _this.preview) || other.preview == _this.preview)&&(identical(other.previewReason, _this.previewReason) || other.previewReason == _this.previewReason)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&(identical(other.editRevision, _this.editRevision) || other.editRevision == _this.editRevision)&&(identical(other.operation, _this.operation) || other.operation == _this.operation)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.catalogReadError, _this.catalogReadError) || other.catalogReadError == _this.catalogReadError)&&(identical(other.notice, _this.notice) || other.notice == _this.notice)&&(identical(other.dialog, _this.dialog) || other.dialog == _this.dialog));
}


@override
int get hashCode {
  final _this = this as ModeEditorViewState;
  return Object.hashAll([runtimeType,_this.catalog,_this.selectedModeId,_this.catalogRevision,_this.draftCatalogRevision,_this.draftOrigin,_this.document,_this.jsonText,_this.jsonApplied,_this.orderText,_this.orderError,const DeepCollectionEquality().hash(_this.criteriaRaw),_this.savedDocument,_this.savedJson,_this.savedRevision,_this.dirty,_this.readOnly,_this.busy,_this.request,const DeepCollectionEquality().hash(_this.undo),const DeepCollectionEquality().hash(_this.redo),_this.tab,_this.selection,_this.inspectorOpen,_this.query,_this.validationRequested,const DeepCollectionEquality().hash(_this.issues),_this.preview,_this.previewReason,_this.latestIntent,_this.editRevision,_this.operation,_this.error,_this.catalogReadError,_this.notice,_this.dialog]);
}



}

/// @nodoc
abstract mixin class $ModeEditorViewStateCopyWith<$Res>  {
  factory $ModeEditorViewStateCopyWith(ModeEditorViewState value, $Res Function(ModeEditorViewState) _then) = _$ModeEditorViewStateCopyWithImpl;
@useResult
$Res call({
 ModesState catalog, String? selectedModeId, int? catalogRevision, int? draftCatalogRevision, ProductReadOrigin? draftOrigin, ModeDocument? document, String jsonText, bool jsonApplied, String orderText, ValidationIssue? orderError, Map<String, String> criteriaRaw, ModeDocument? savedDocument, String savedJson, int? savedRevision, bool dirty, bool readOnly, bool busy, ModeEditorRequest? request, List<ModeEditorSnapshot> undo, List<ModeEditorSnapshot> redo, ModeEditorTab tab, ModeEditorSelection selection, bool inspectorOpen, String query, bool validationRequested, List<ValidationIssue> issues, WorkflowPreviewSnapshot? preview, String previewReason, int latestIntent, int editRevision, SettingsAction? operation, StudioFailure? error, StudioFailure? catalogReadError, ModeEditorNotice? notice, ModeDialogDraft? dialog
});


$ModesStateCopyWith<$Res> get catalog;$ProductReadOriginCopyWith<$Res>? get draftOrigin;$ModeDocumentCopyWith<$Res>? get document;$ValidationIssueCopyWith<$Res>? get orderError;$ModeDocumentCopyWith<$Res>? get savedDocument;$ModeEditorSelectionCopyWith<$Res> get selection;$WorkflowPreviewSnapshotCopyWith<$Res>? get preview;$SettingsActionCopyWith<$Res>? get operation;$StudioFailureCopyWith<$Res>? get error;$StudioFailureCopyWith<$Res>? get catalogReadError;$ModeDialogDraftCopyWith<$Res>? get dialog;

}
/// @nodoc
class _$ModeEditorViewStateCopyWithImpl<$Res>
    implements $ModeEditorViewStateCopyWith<$Res> {
  _$ModeEditorViewStateCopyWithImpl(this._self, this._then);

  final ModeEditorViewState _self;
  final $Res Function(ModeEditorViewState) _then;

/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? catalog = null,Object? selectedModeId = freezed,Object? catalogRevision = freezed,Object? draftCatalogRevision = freezed,Object? draftOrigin = freezed,Object? document = freezed,Object? jsonText = null,Object? jsonApplied = null,Object? orderText = null,Object? orderError = freezed,Object? criteriaRaw = null,Object? savedDocument = freezed,Object? savedJson = null,Object? savedRevision = freezed,Object? dirty = null,Object? readOnly = null,Object? busy = null,Object? request = freezed,Object? undo = null,Object? redo = null,Object? tab = null,Object? selection = null,Object? inspectorOpen = null,Object? query = null,Object? validationRequested = null,Object? issues = null,Object? preview = freezed,Object? previewReason = null,Object? latestIntent = null,Object? editRevision = null,Object? operation = freezed,Object? error = freezed,Object? catalogReadError = freezed,Object? notice = freezed,Object? dialog = freezed,}) {
  return _then(ModeEditorViewState(
catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModesState,selectedModeId: freezed == selectedModeId ? _self.selectedModeId : selectedModeId // ignore: cast_nullable_to_non_nullable
as String?,catalogRevision: freezed == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int?,draftCatalogRevision: freezed == draftCatalogRevision ? _self.draftCatalogRevision : draftCatalogRevision // ignore: cast_nullable_to_non_nullable
as int?,draftOrigin: freezed == draftOrigin ? _self.draftOrigin : draftOrigin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin?,document: freezed == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as ModeDocument?,jsonText: null == jsonText ? _self.jsonText : jsonText // ignore: cast_nullable_to_non_nullable
as String,jsonApplied: null == jsonApplied ? _self.jsonApplied : jsonApplied // ignore: cast_nullable_to_non_nullable
as bool,orderText: null == orderText ? _self.orderText : orderText // ignore: cast_nullable_to_non_nullable
as String,orderError: freezed == orderError ? _self.orderError : orderError // ignore: cast_nullable_to_non_nullable
as ValidationIssue?,criteriaRaw: null == criteriaRaw ? _self.criteriaRaw : criteriaRaw // ignore: cast_nullable_to_non_nullable
as Map<String, String>,savedDocument: freezed == savedDocument ? _self.savedDocument : savedDocument // ignore: cast_nullable_to_non_nullable
as ModeDocument?,savedJson: null == savedJson ? _self.savedJson : savedJson // ignore: cast_nullable_to_non_nullable
as String,savedRevision: freezed == savedRevision ? _self.savedRevision : savedRevision // ignore: cast_nullable_to_non_nullable
as int?,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,readOnly: null == readOnly ? _self.readOnly : readOnly // ignore: cast_nullable_to_non_nullable
as bool,busy: null == busy ? _self.busy : busy // ignore: cast_nullable_to_non_nullable
as bool,request: freezed == request ? _self.request : request // ignore: cast_nullable_to_non_nullable
as ModeEditorRequest?,undo: null == undo ? _self.undo : undo // ignore: cast_nullable_to_non_nullable
as List<ModeEditorSnapshot>,redo: null == redo ? _self.redo : redo // ignore: cast_nullable_to_non_nullable
as List<ModeEditorSnapshot>,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as ModeEditorTab,selection: null == selection ? _self.selection : selection // ignore: cast_nullable_to_non_nullable
as ModeEditorSelection,inspectorOpen: null == inspectorOpen ? _self.inspectorOpen : inspectorOpen // ignore: cast_nullable_to_non_nullable
as bool,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,validationRequested: null == validationRequested ? _self.validationRequested : validationRequested // ignore: cast_nullable_to_non_nullable
as bool,issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as List<ValidationIssue>,preview: freezed == preview ? _self.preview : preview // ignore: cast_nullable_to_non_nullable
as WorkflowPreviewSnapshot?,previewReason: null == previewReason ? _self.previewReason : previewReason // ignore: cast_nullable_to_non_nullable
as String,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,editRevision: null == editRevision ? _self.editRevision : editRevision // ignore: cast_nullable_to_non_nullable
as int,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as SettingsAction?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,catalogReadError: freezed == catalogReadError ? _self.catalogReadError : catalogReadError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,notice: freezed == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as ModeEditorNotice?,dialog: freezed == dialog ? _self.dialog : dialog // ignore: cast_nullable_to_non_nullable
as ModeDialogDraft?,
  ));
}
/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModesStateCopyWith<$Res> get catalog {

  return $ModesStateCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res>? get draftOrigin {
    if (_self.draftOrigin == null) {
    return null;
  }

  return $ProductReadOriginCopyWith<$Res>(_self.draftOrigin!, (value) {
    return _then(_self.copyWith(draftOrigin: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDocumentCopyWith<$Res>? get document {
    if (_self.document == null) {
    return null;
  }

  return $ModeDocumentCopyWith<$Res>(_self.document!, (value) {
    return _then(_self.copyWith(document: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ValidationIssueCopyWith<$Res>? get orderError {
    if (_self.orderError == null) {
    return null;
  }

  return $ValidationIssueCopyWith<$Res>(_self.orderError!, (value) {
    return _then(_self.copyWith(orderError: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDocumentCopyWith<$Res>? get savedDocument {
    if (_self.savedDocument == null) {
    return null;
  }

  return $ModeDocumentCopyWith<$Res>(_self.savedDocument!, (value) {
    return _then(_self.copyWith(savedDocument: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeEditorSelectionCopyWith<$Res> get selection {

  return $ModeEditorSelectionCopyWith<$Res>(_self.selection, (value) {
    return _then(_self.copyWith(selection: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowPreviewSnapshotCopyWith<$Res>? get preview {
    if (_self.preview == null) {
    return null;
  }

  return $WorkflowPreviewSnapshotCopyWith<$Res>(_self.preview!, (value) {
    return _then(_self.copyWith(preview: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of ModeEditorViewState
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
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get catalogReadError {
    if (_self.catalogReadError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.catalogReadError!, (value) {
    return _then(_self.copyWith(catalogReadError: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDialogDraftCopyWith<$Res>? get dialog {
    if (_self.dialog == null) {
    return null;
  }

  return $ModeDialogDraftCopyWith<$Res>(_self.dialog!, (value) {
    return _then(_self.copyWith(dialog: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeEditorViewState].
extension ModeEditorViewStatePatterns on ModeEditorViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeEditorViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeEditorViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeEditorViewState value)  $default,){
final _that = this;
switch (_that) {
case _ModeEditorViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeEditorViewState value)?  $default,){
final _that = this;
switch (_that) {
case _ModeEditorViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModesState catalog,  String? selectedModeId,  int? catalogRevision,  int? draftCatalogRevision,  ProductReadOrigin? draftOrigin,  ModeDocument? document,  String jsonText,  bool jsonApplied,  String orderText,  ValidationIssue? orderError,  Map<String, String> criteriaRaw,  ModeDocument? savedDocument,  String savedJson,  int? savedRevision,  bool dirty,  bool readOnly,  bool busy,  ModeEditorRequest? request,  List<ModeEditorSnapshot> undo,  List<ModeEditorSnapshot> redo,  ModeEditorTab tab,  ModeEditorSelection selection,  bool inspectorOpen,  String query,  bool validationRequested,  List<ValidationIssue> issues,  WorkflowPreviewSnapshot? preview,  String previewReason,  int latestIntent,  int editRevision,  SettingsAction? operation,  StudioFailure? error,  StudioFailure? catalogReadError,  ModeEditorNotice? notice,  ModeDialogDraft? dialog)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeEditorViewState() when $default != null:
return $default(_that.catalog,_that.selectedModeId,_that.catalogRevision,_that.draftCatalogRevision,_that.draftOrigin,_that.document,_that.jsonText,_that.jsonApplied,_that.orderText,_that.orderError,_that.criteriaRaw,_that.savedDocument,_that.savedJson,_that.savedRevision,_that.dirty,_that.readOnly,_that.busy,_that.request,_that.undo,_that.redo,_that.tab,_that.selection,_that.inspectorOpen,_that.query,_that.validationRequested,_that.issues,_that.preview,_that.previewReason,_that.latestIntent,_that.editRevision,_that.operation,_that.error,_that.catalogReadError,_that.notice,_that.dialog);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModesState catalog,  String? selectedModeId,  int? catalogRevision,  int? draftCatalogRevision,  ProductReadOrigin? draftOrigin,  ModeDocument? document,  String jsonText,  bool jsonApplied,  String orderText,  ValidationIssue? orderError,  Map<String, String> criteriaRaw,  ModeDocument? savedDocument,  String savedJson,  int? savedRevision,  bool dirty,  bool readOnly,  bool busy,  ModeEditorRequest? request,  List<ModeEditorSnapshot> undo,  List<ModeEditorSnapshot> redo,  ModeEditorTab tab,  ModeEditorSelection selection,  bool inspectorOpen,  String query,  bool validationRequested,  List<ValidationIssue> issues,  WorkflowPreviewSnapshot? preview,  String previewReason,  int latestIntent,  int editRevision,  SettingsAction? operation,  StudioFailure? error,  StudioFailure? catalogReadError,  ModeEditorNotice? notice,  ModeDialogDraft? dialog)  $default,) {final _that = this;
switch (_that) {
case _ModeEditorViewState():
return $default(_that.catalog,_that.selectedModeId,_that.catalogRevision,_that.draftCatalogRevision,_that.draftOrigin,_that.document,_that.jsonText,_that.jsonApplied,_that.orderText,_that.orderError,_that.criteriaRaw,_that.savedDocument,_that.savedJson,_that.savedRevision,_that.dirty,_that.readOnly,_that.busy,_that.request,_that.undo,_that.redo,_that.tab,_that.selection,_that.inspectorOpen,_that.query,_that.validationRequested,_that.issues,_that.preview,_that.previewReason,_that.latestIntent,_that.editRevision,_that.operation,_that.error,_that.catalogReadError,_that.notice,_that.dialog);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModesState catalog,  String? selectedModeId,  int? catalogRevision,  int? draftCatalogRevision,  ProductReadOrigin? draftOrigin,  ModeDocument? document,  String jsonText,  bool jsonApplied,  String orderText,  ValidationIssue? orderError,  Map<String, String> criteriaRaw,  ModeDocument? savedDocument,  String savedJson,  int? savedRevision,  bool dirty,  bool readOnly,  bool busy,  ModeEditorRequest? request,  List<ModeEditorSnapshot> undo,  List<ModeEditorSnapshot> redo,  ModeEditorTab tab,  ModeEditorSelection selection,  bool inspectorOpen,  String query,  bool validationRequested,  List<ValidationIssue> issues,  WorkflowPreviewSnapshot? preview,  String previewReason,  int latestIntent,  int editRevision,  SettingsAction? operation,  StudioFailure? error,  StudioFailure? catalogReadError,  ModeEditorNotice? notice,  ModeDialogDraft? dialog)?  $default,) {final _that = this;
switch (_that) {
case _ModeEditorViewState() when $default != null:
return $default(_that.catalog,_that.selectedModeId,_that.catalogRevision,_that.draftCatalogRevision,_that.draftOrigin,_that.document,_that.jsonText,_that.jsonApplied,_that.orderText,_that.orderError,_that.criteriaRaw,_that.savedDocument,_that.savedJson,_that.savedRevision,_that.dirty,_that.readOnly,_that.busy,_that.request,_that.undo,_that.redo,_that.tab,_that.selection,_that.inspectorOpen,_that.query,_that.validationRequested,_that.issues,_that.preview,_that.previewReason,_that.latestIntent,_that.editRevision,_that.operation,_that.error,_that.catalogReadError,_that.notice,_that.dialog);case _:
  return null;

}
}

}

/// @nodoc


class _ModeEditorViewState extends ModeEditorViewState {
  const _ModeEditorViewState({required this.catalog, this.selectedModeId, this.catalogRevision, this.draftCatalogRevision, this.draftOrigin, this.document, this.jsonText = '', this.jsonApplied = true, this.orderText = '', this.orderError,  Map<String, String> criteriaRaw = const {}, this.savedDocument, this.savedJson = '', this.savedRevision, this.dirty = false, this.readOnly = false, this.busy = false, this.request,  List<ModeEditorSnapshot> undo = const [],  List<ModeEditorSnapshot> redo = const [], this.tab = ModeEditorTab.graph, this.selection = const ModeEditorSelection.none(), this.inspectorOpen = false, this.query = '', this.validationRequested = false,  List<ValidationIssue> issues = const [], this.preview, this.previewReason = '', this.latestIntent = 0, this.editRevision = 0, this.operation, this.error, this.catalogReadError, this.notice, this.dialog}): _criteriaRaw = criteriaRaw,_undo = undo,_redo = redo,_issues = issues,super._();


@override final  ModesState catalog;
@override final  String? selectedModeId;
@override final  int? catalogRevision;
@override final  int? draftCatalogRevision;
@override final  ProductReadOrigin? draftOrigin;
@override final  ModeDocument? document;
@override@JsonKey() final  String jsonText;
@override@JsonKey() final  bool jsonApplied;
@override@JsonKey() final  String orderText;
@override final  ValidationIssue? orderError;
 final  Map<String, String> _criteriaRaw;
@override@JsonKey() Map<String, String> get criteriaRaw {
  if (_criteriaRaw is EqualUnmodifiableMapView) return _criteriaRaw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_criteriaRaw);
}

@override final  ModeDocument? savedDocument;
@override@JsonKey() final  String savedJson;
@override final  int? savedRevision;
@override@JsonKey() final  bool dirty;
@override@JsonKey() final  bool readOnly;
@override@JsonKey() final  bool busy;
@override final  ModeEditorRequest? request;
 final  List<ModeEditorSnapshot> _undo;
@override@JsonKey() List<ModeEditorSnapshot> get undo {
  if (_undo is EqualUnmodifiableListView) return _undo;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_undo);
}

 final  List<ModeEditorSnapshot> _redo;
@override@JsonKey() List<ModeEditorSnapshot> get redo {
  if (_redo is EqualUnmodifiableListView) return _redo;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_redo);
}

@override@JsonKey() final  ModeEditorTab tab;
@override@JsonKey() final  ModeEditorSelection selection;
@override@JsonKey() final  bool inspectorOpen;
@override@JsonKey() final  String query;
@override@JsonKey() final  bool validationRequested;
 final  List<ValidationIssue> _issues;
@override@JsonKey() List<ValidationIssue> get issues {
  if (_issues is EqualUnmodifiableListView) return _issues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_issues);
}

@override final  WorkflowPreviewSnapshot? preview;
@override@JsonKey() final  String previewReason;
@override@JsonKey() final  int latestIntent;
@override@JsonKey() final  int editRevision;
@override final  SettingsAction? operation;
@override final  StudioFailure? error;
@override final  StudioFailure? catalogReadError;
@override final  ModeEditorNotice? notice;
@override final  ModeDialogDraft? dialog;

/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeEditorViewStateCopyWith<_ModeEditorViewState> get copyWith => __$ModeEditorViewStateCopyWithImpl<_ModeEditorViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeEditorViewState&&(identical(other.catalog, catalog) || other.catalog == catalog)&&(identical(other.selectedModeId, selectedModeId) || other.selectedModeId == selectedModeId)&&(identical(other.catalogRevision, catalogRevision) || other.catalogRevision == catalogRevision)&&(identical(other.draftCatalogRevision, draftCatalogRevision) || other.draftCatalogRevision == draftCatalogRevision)&&(identical(other.draftOrigin, draftOrigin) || other.draftOrigin == draftOrigin)&&(identical(other.document, document) || other.document == document)&&(identical(other.jsonText, jsonText) || other.jsonText == jsonText)&&(identical(other.jsonApplied, jsonApplied) || other.jsonApplied == jsonApplied)&&(identical(other.orderText, orderText) || other.orderText == orderText)&&(identical(other.orderError, orderError) || other.orderError == orderError)&&const DeepCollectionEquality().equals(other.criteriaRaw, _criteriaRaw)&&(identical(other.savedDocument, savedDocument) || other.savedDocument == savedDocument)&&(identical(other.savedJson, savedJson) || other.savedJson == savedJson)&&(identical(other.savedRevision, savedRevision) || other.savedRevision == savedRevision)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.readOnly, readOnly) || other.readOnly == readOnly)&&(identical(other.busy, busy) || other.busy == busy)&&(identical(other.request, request) || other.request == request)&&const DeepCollectionEquality().equals(other.undo, _undo)&&const DeepCollectionEquality().equals(other.redo, _redo)&&(identical(other.tab, tab) || other.tab == tab)&&(identical(other.selection, selection) || other.selection == selection)&&(identical(other.inspectorOpen, inspectorOpen) || other.inspectorOpen == inspectorOpen)&&(identical(other.query, query) || other.query == query)&&(identical(other.validationRequested, validationRequested) || other.validationRequested == validationRequested)&&const DeepCollectionEquality().equals(other.issues, _issues)&&(identical(other.preview, preview) || other.preview == preview)&&(identical(other.previewReason, previewReason) || other.previewReason == previewReason)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&(identical(other.editRevision, editRevision) || other.editRevision == editRevision)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.error, error) || other.error == error)&&(identical(other.catalogReadError, catalogReadError) || other.catalogReadError == catalogReadError)&&(identical(other.notice, notice) || other.notice == notice)&&(identical(other.dialog, dialog) || other.dialog == dialog));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,catalog,selectedModeId,catalogRevision,draftCatalogRevision,draftOrigin,document,jsonText,jsonApplied,orderText,orderError,const DeepCollectionEquality().hash(_criteriaRaw),savedDocument,savedJson,savedRevision,dirty,readOnly,busy,request,const DeepCollectionEquality().hash(_undo),const DeepCollectionEquality().hash(_redo),tab,selection,inspectorOpen,query,validationRequested,const DeepCollectionEquality().hash(_issues),preview,previewReason,latestIntent,editRevision,operation,error,catalogReadError,notice,dialog]);
}



}

/// @nodoc
abstract mixin class _$ModeEditorViewStateCopyWith<$Res> implements $ModeEditorViewStateCopyWith<$Res> {
  factory _$ModeEditorViewStateCopyWith(_ModeEditorViewState value, $Res Function(_ModeEditorViewState) _then) = __$ModeEditorViewStateCopyWithImpl;
@override @useResult
$Res call({
 ModesState catalog, String? selectedModeId, int? catalogRevision, int? draftCatalogRevision, ProductReadOrigin? draftOrigin, ModeDocument? document, String jsonText, bool jsonApplied, String orderText, ValidationIssue? orderError, Map<String, String> criteriaRaw, ModeDocument? savedDocument, String savedJson, int? savedRevision, bool dirty, bool readOnly, bool busy, ModeEditorRequest? request, List<ModeEditorSnapshot> undo, List<ModeEditorSnapshot> redo, ModeEditorTab tab, ModeEditorSelection selection, bool inspectorOpen, String query, bool validationRequested, List<ValidationIssue> issues, WorkflowPreviewSnapshot? preview, String previewReason, int latestIntent, int editRevision, SettingsAction? operation, StudioFailure? error, StudioFailure? catalogReadError, ModeEditorNotice? notice, ModeDialogDraft? dialog
});


@override $ModesStateCopyWith<$Res> get catalog;@override $ProductReadOriginCopyWith<$Res>? get draftOrigin;@override $ModeDocumentCopyWith<$Res>? get document;@override $ValidationIssueCopyWith<$Res>? get orderError;@override $ModeDocumentCopyWith<$Res>? get savedDocument;@override $ModeEditorSelectionCopyWith<$Res> get selection;@override $WorkflowPreviewSnapshotCopyWith<$Res>? get preview;@override $SettingsActionCopyWith<$Res>? get operation;@override $StudioFailureCopyWith<$Res>? get error;@override $StudioFailureCopyWith<$Res>? get catalogReadError;@override $ModeDialogDraftCopyWith<$Res>? get dialog;

}
/// @nodoc
class __$ModeEditorViewStateCopyWithImpl<$Res>
    implements _$ModeEditorViewStateCopyWith<$Res> {
  __$ModeEditorViewStateCopyWithImpl(this._self, this._then);

  final _ModeEditorViewState _self;
  final $Res Function(_ModeEditorViewState) _then;

/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? catalog = null,Object? selectedModeId = freezed,Object? catalogRevision = freezed,Object? draftCatalogRevision = freezed,Object? draftOrigin = freezed,Object? document = freezed,Object? jsonText = null,Object? jsonApplied = null,Object? orderText = null,Object? orderError = freezed,Object? criteriaRaw = null,Object? savedDocument = freezed,Object? savedJson = null,Object? savedRevision = freezed,Object? dirty = null,Object? readOnly = null,Object? busy = null,Object? request = freezed,Object? undo = null,Object? redo = null,Object? tab = null,Object? selection = null,Object? inspectorOpen = null,Object? query = null,Object? validationRequested = null,Object? issues = null,Object? preview = freezed,Object? previewReason = null,Object? latestIntent = null,Object? editRevision = null,Object? operation = freezed,Object? error = freezed,Object? catalogReadError = freezed,Object? notice = freezed,Object? dialog = freezed,}) {
  return _then(_ModeEditorViewState(
catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModesState,selectedModeId: freezed == selectedModeId ? _self.selectedModeId : selectedModeId // ignore: cast_nullable_to_non_nullable
as String?,catalogRevision: freezed == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int?,draftCatalogRevision: freezed == draftCatalogRevision ? _self.draftCatalogRevision : draftCatalogRevision // ignore: cast_nullable_to_non_nullable
as int?,draftOrigin: freezed == draftOrigin ? _self.draftOrigin : draftOrigin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin?,document: freezed == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as ModeDocument?,jsonText: null == jsonText ? _self.jsonText : jsonText // ignore: cast_nullable_to_non_nullable
as String,jsonApplied: null == jsonApplied ? _self.jsonApplied : jsonApplied // ignore: cast_nullable_to_non_nullable
as bool,orderText: null == orderText ? _self.orderText : orderText // ignore: cast_nullable_to_non_nullable
as String,orderError: freezed == orderError ? _self.orderError : orderError // ignore: cast_nullable_to_non_nullable
as ValidationIssue?,criteriaRaw: null == criteriaRaw ? _self._criteriaRaw : criteriaRaw // ignore: cast_nullable_to_non_nullable
as Map<String, String>,savedDocument: freezed == savedDocument ? _self.savedDocument : savedDocument // ignore: cast_nullable_to_non_nullable
as ModeDocument?,savedJson: null == savedJson ? _self.savedJson : savedJson // ignore: cast_nullable_to_non_nullable
as String,savedRevision: freezed == savedRevision ? _self.savedRevision : savedRevision // ignore: cast_nullable_to_non_nullable
as int?,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,readOnly: null == readOnly ? _self.readOnly : readOnly // ignore: cast_nullable_to_non_nullable
as bool,busy: null == busy ? _self.busy : busy // ignore: cast_nullable_to_non_nullable
as bool,request: freezed == request ? _self.request : request // ignore: cast_nullable_to_non_nullable
as ModeEditorRequest?,undo: null == undo ? _self._undo : undo // ignore: cast_nullable_to_non_nullable
as List<ModeEditorSnapshot>,redo: null == redo ? _self._redo : redo // ignore: cast_nullable_to_non_nullable
as List<ModeEditorSnapshot>,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as ModeEditorTab,selection: null == selection ? _self.selection : selection // ignore: cast_nullable_to_non_nullable
as ModeEditorSelection,inspectorOpen: null == inspectorOpen ? _self.inspectorOpen : inspectorOpen // ignore: cast_nullable_to_non_nullable
as bool,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,validationRequested: null == validationRequested ? _self.validationRequested : validationRequested // ignore: cast_nullable_to_non_nullable
as bool,issues: null == issues ? _self._issues : issues // ignore: cast_nullable_to_non_nullable
as List<ValidationIssue>,preview: freezed == preview ? _self.preview : preview // ignore: cast_nullable_to_non_nullable
as WorkflowPreviewSnapshot?,previewReason: null == previewReason ? _self.previewReason : previewReason // ignore: cast_nullable_to_non_nullable
as String,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,editRevision: null == editRevision ? _self.editRevision : editRevision // ignore: cast_nullable_to_non_nullable
as int,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as SettingsAction?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,catalogReadError: freezed == catalogReadError ? _self.catalogReadError : catalogReadError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,notice: freezed == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as ModeEditorNotice?,dialog: freezed == dialog ? _self.dialog : dialog // ignore: cast_nullable_to_non_nullable
as ModeDialogDraft?,
  ));
}

/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModesStateCopyWith<$Res> get catalog {

  return $ModesStateCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res>? get draftOrigin {
    if (_self.draftOrigin == null) {
    return null;
  }

  return $ProductReadOriginCopyWith<$Res>(_self.draftOrigin!, (value) {
    return _then(_self.copyWith(draftOrigin: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDocumentCopyWith<$Res>? get document {
    if (_self.document == null) {
    return null;
  }

  return $ModeDocumentCopyWith<$Res>(_self.document!, (value) {
    return _then(_self.copyWith(document: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ValidationIssueCopyWith<$Res>? get orderError {
    if (_self.orderError == null) {
    return null;
  }

  return $ValidationIssueCopyWith<$Res>(_self.orderError!, (value) {
    return _then(_self.copyWith(orderError: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDocumentCopyWith<$Res>? get savedDocument {
    if (_self.savedDocument == null) {
    return null;
  }

  return $ModeDocumentCopyWith<$Res>(_self.savedDocument!, (value) {
    return _then(_self.copyWith(savedDocument: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeEditorSelectionCopyWith<$Res> get selection {

  return $ModeEditorSelectionCopyWith<$Res>(_self.selection, (value) {
    return _then(_self.copyWith(selection: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowPreviewSnapshotCopyWith<$Res>? get preview {
    if (_self.preview == null) {
    return null;
  }

  return $WorkflowPreviewSnapshotCopyWith<$Res>(_self.preview!, (value) {
    return _then(_self.copyWith(preview: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of ModeEditorViewState
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
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get catalogReadError {
    if (_self.catalogReadError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.catalogReadError!, (value) {
    return _then(_self.copyWith(catalogReadError: value));
  });
}/// Create a copy of ModeEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDialogDraftCopyWith<$Res>? get dialog {
    if (_self.dialog == null) {
    return null;
  }

  return $ModeDialogDraftCopyWith<$Res>(_self.dialog!, (value) {
    return _then(_self.copyWith(dialog: value));
  });
}
}

/// @nodoc
mixin _$ModeEdit {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeEdit);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ModeEditCopyWith<$Res>  {
$ModeEditCopyWith(ModeEdit _, $Res Function(ModeEdit) __);
}


/// Adds pattern-matching-related methods to [ModeEdit].
extension ModeEditPatterns on ModeEdit {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( EditModeDisplayName value)?  displayName,TResult Function( EditModeDescription value)?  description,TResult Function( EditModeOrder value)?  orderRaw,TResult Function( EditModePrompt value)?  prompt,TResult Function( EditWorkflowTitle value)?  workflowTitle,TResult Function( EditWorkflowGoal value)?  workflowGoal,TResult Function( EditInitialState value)?  initialState,TResult Function( AddWorkflowState value)?  addState,TResult Function( RenameWorkflowState value)?  renameState,TResult Function( RemoveWorkflowState value)?  removeState,TResult Function( EditWorkflowStateTitle value)?  stateTitle,TResult Function( EditWorkflowStateInstructions value)?  stateInstructions,TResult Function( EditWorkflowStateCriteria value)?  stateCriteria,TResult Function( EditWorkflowStateKind value)?  stateKind,TResult Function( AddWorkflowTransition value)?  addTransition,TResult Function( RemoveWorkflowTransition value)?  removeTransition,TResult Function( EditWorkflowTransitionGuard value)?  transitionGuard,TResult Function( EditWorkflowNodePositions value)?  nodePositions,TResult Function( EnableModeWorkflow value)?  enableWorkflow,TResult Function( RemoveModeWorkflow value)?  removeWorkflow,required TResult orElse(),}){
final _that = this;
switch (_that) {
case EditModeDisplayName() when displayName != null:
return displayName(_that);case EditModeDescription() when description != null:
return description(_that);case EditModeOrder() when orderRaw != null:
return orderRaw(_that);case EditModePrompt() when prompt != null:
return prompt(_that);case EditWorkflowTitle() when workflowTitle != null:
return workflowTitle(_that);case EditWorkflowGoal() when workflowGoal != null:
return workflowGoal(_that);case EditInitialState() when initialState != null:
return initialState(_that);case AddWorkflowState() when addState != null:
return addState(_that);case RenameWorkflowState() when renameState != null:
return renameState(_that);case RemoveWorkflowState() when removeState != null:
return removeState(_that);case EditWorkflowStateTitle() when stateTitle != null:
return stateTitle(_that);case EditWorkflowStateInstructions() when stateInstructions != null:
return stateInstructions(_that);case EditWorkflowStateCriteria() when stateCriteria != null:
return stateCriteria(_that);case EditWorkflowStateKind() when stateKind != null:
return stateKind(_that);case AddWorkflowTransition() when addTransition != null:
return addTransition(_that);case RemoveWorkflowTransition() when removeTransition != null:
return removeTransition(_that);case EditWorkflowTransitionGuard() when transitionGuard != null:
return transitionGuard(_that);case EditWorkflowNodePositions() when nodePositions != null:
return nodePositions(_that);case EnableModeWorkflow() when enableWorkflow != null:
return enableWorkflow(_that);case RemoveModeWorkflow() when removeWorkflow != null:
return removeWorkflow(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( EditModeDisplayName value)  displayName,required TResult Function( EditModeDescription value)  description,required TResult Function( EditModeOrder value)  orderRaw,required TResult Function( EditModePrompt value)  prompt,required TResult Function( EditWorkflowTitle value)  workflowTitle,required TResult Function( EditWorkflowGoal value)  workflowGoal,required TResult Function( EditInitialState value)  initialState,required TResult Function( AddWorkflowState value)  addState,required TResult Function( RenameWorkflowState value)  renameState,required TResult Function( RemoveWorkflowState value)  removeState,required TResult Function( EditWorkflowStateTitle value)  stateTitle,required TResult Function( EditWorkflowStateInstructions value)  stateInstructions,required TResult Function( EditWorkflowStateCriteria value)  stateCriteria,required TResult Function( EditWorkflowStateKind value)  stateKind,required TResult Function( AddWorkflowTransition value)  addTransition,required TResult Function( RemoveWorkflowTransition value)  removeTransition,required TResult Function( EditWorkflowTransitionGuard value)  transitionGuard,required TResult Function( EditWorkflowNodePositions value)  nodePositions,required TResult Function( EnableModeWorkflow value)  enableWorkflow,required TResult Function( RemoveModeWorkflow value)  removeWorkflow,}){
final _that = this;
switch (_that) {
case EditModeDisplayName():
return displayName(_that);case EditModeDescription():
return description(_that);case EditModeOrder():
return orderRaw(_that);case EditModePrompt():
return prompt(_that);case EditWorkflowTitle():
return workflowTitle(_that);case EditWorkflowGoal():
return workflowGoal(_that);case EditInitialState():
return initialState(_that);case AddWorkflowState():
return addState(_that);case RenameWorkflowState():
return renameState(_that);case RemoveWorkflowState():
return removeState(_that);case EditWorkflowStateTitle():
return stateTitle(_that);case EditWorkflowStateInstructions():
return stateInstructions(_that);case EditWorkflowStateCriteria():
return stateCriteria(_that);case EditWorkflowStateKind():
return stateKind(_that);case AddWorkflowTransition():
return addTransition(_that);case RemoveWorkflowTransition():
return removeTransition(_that);case EditWorkflowTransitionGuard():
return transitionGuard(_that);case EditWorkflowNodePositions():
return nodePositions(_that);case EnableModeWorkflow():
return enableWorkflow(_that);case RemoveModeWorkflow():
return removeWorkflow(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( EditModeDisplayName value)?  displayName,TResult? Function( EditModeDescription value)?  description,TResult? Function( EditModeOrder value)?  orderRaw,TResult? Function( EditModePrompt value)?  prompt,TResult? Function( EditWorkflowTitle value)?  workflowTitle,TResult? Function( EditWorkflowGoal value)?  workflowGoal,TResult? Function( EditInitialState value)?  initialState,TResult? Function( AddWorkflowState value)?  addState,TResult? Function( RenameWorkflowState value)?  renameState,TResult? Function( RemoveWorkflowState value)?  removeState,TResult? Function( EditWorkflowStateTitle value)?  stateTitle,TResult? Function( EditWorkflowStateInstructions value)?  stateInstructions,TResult? Function( EditWorkflowStateCriteria value)?  stateCriteria,TResult? Function( EditWorkflowStateKind value)?  stateKind,TResult? Function( AddWorkflowTransition value)?  addTransition,TResult? Function( RemoveWorkflowTransition value)?  removeTransition,TResult? Function( EditWorkflowTransitionGuard value)?  transitionGuard,TResult? Function( EditWorkflowNodePositions value)?  nodePositions,TResult? Function( EnableModeWorkflow value)?  enableWorkflow,TResult? Function( RemoveModeWorkflow value)?  removeWorkflow,}){
final _that = this;
switch (_that) {
case EditModeDisplayName() when displayName != null:
return displayName(_that);case EditModeDescription() when description != null:
return description(_that);case EditModeOrder() when orderRaw != null:
return orderRaw(_that);case EditModePrompt() when prompt != null:
return prompt(_that);case EditWorkflowTitle() when workflowTitle != null:
return workflowTitle(_that);case EditWorkflowGoal() when workflowGoal != null:
return workflowGoal(_that);case EditInitialState() when initialState != null:
return initialState(_that);case AddWorkflowState() when addState != null:
return addState(_that);case RenameWorkflowState() when renameState != null:
return renameState(_that);case RemoveWorkflowState() when removeState != null:
return removeState(_that);case EditWorkflowStateTitle() when stateTitle != null:
return stateTitle(_that);case EditWorkflowStateInstructions() when stateInstructions != null:
return stateInstructions(_that);case EditWorkflowStateCriteria() when stateCriteria != null:
return stateCriteria(_that);case EditWorkflowStateKind() when stateKind != null:
return stateKind(_that);case AddWorkflowTransition() when addTransition != null:
return addTransition(_that);case RemoveWorkflowTransition() when removeTransition != null:
return removeTransition(_that);case EditWorkflowTransitionGuard() when transitionGuard != null:
return transitionGuard(_that);case EditWorkflowNodePositions() when nodePositions != null:
return nodePositions(_that);case EnableModeWorkflow() when enableWorkflow != null:
return enableWorkflow(_that);case RemoveModeWorkflow() when removeWorkflow != null:
return removeWorkflow(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String value)?  displayName,TResult Function( String value)?  description,TResult Function( String value)?  orderRaw,TResult Function( String value)?  prompt,TResult Function( String value)?  workflowTitle,TResult Function( String value)?  workflowGoal,TResult Function( String value)?  initialState,TResult Function( WorkflowState value)?  addState,TResult Function( String oldId,  String newId)?  renameState,TResult Function( String id)?  removeState,TResult Function( String id,  String value)?  stateTitle,TResult Function( String id,  String value)?  stateInstructions,TResult Function( String id,  List<String> values)?  stateCriteria,TResult Function( String id,  WorkflowStateKind value)?  stateKind,TResult Function( WorkflowTransition value)?  addTransition,TResult Function( String sourceId,  String targetId)?  removeTransition,TResult Function( String sourceId,  String targetId,  String value)?  transitionGuard,TResult Function( List<WorkflowNodePosition> values)?  nodePositions,TResult Function( WorkflowDefinition value)?  enableWorkflow,TResult Function()?  removeWorkflow,required TResult orElse(),}) {final _that = this;
switch (_that) {
case EditModeDisplayName() when displayName != null:
return displayName(_that.value);case EditModeDescription() when description != null:
return description(_that.value);case EditModeOrder() when orderRaw != null:
return orderRaw(_that.value);case EditModePrompt() when prompt != null:
return prompt(_that.value);case EditWorkflowTitle() when workflowTitle != null:
return workflowTitle(_that.value);case EditWorkflowGoal() when workflowGoal != null:
return workflowGoal(_that.value);case EditInitialState() when initialState != null:
return initialState(_that.value);case AddWorkflowState() when addState != null:
return addState(_that.value);case RenameWorkflowState() when renameState != null:
return renameState(_that.oldId,_that.newId);case RemoveWorkflowState() when removeState != null:
return removeState(_that.id);case EditWorkflowStateTitle() when stateTitle != null:
return stateTitle(_that.id,_that.value);case EditWorkflowStateInstructions() when stateInstructions != null:
return stateInstructions(_that.id,_that.value);case EditWorkflowStateCriteria() when stateCriteria != null:
return stateCriteria(_that.id,_that.values);case EditWorkflowStateKind() when stateKind != null:
return stateKind(_that.id,_that.value);case AddWorkflowTransition() when addTransition != null:
return addTransition(_that.value);case RemoveWorkflowTransition() when removeTransition != null:
return removeTransition(_that.sourceId,_that.targetId);case EditWorkflowTransitionGuard() when transitionGuard != null:
return transitionGuard(_that.sourceId,_that.targetId,_that.value);case EditWorkflowNodePositions() when nodePositions != null:
return nodePositions(_that.values);case EnableModeWorkflow() when enableWorkflow != null:
return enableWorkflow(_that.value);case RemoveModeWorkflow() when removeWorkflow != null:
return removeWorkflow();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String value)  displayName,required TResult Function( String value)  description,required TResult Function( String value)  orderRaw,required TResult Function( String value)  prompt,required TResult Function( String value)  workflowTitle,required TResult Function( String value)  workflowGoal,required TResult Function( String value)  initialState,required TResult Function( WorkflowState value)  addState,required TResult Function( String oldId,  String newId)  renameState,required TResult Function( String id)  removeState,required TResult Function( String id,  String value)  stateTitle,required TResult Function( String id,  String value)  stateInstructions,required TResult Function( String id,  List<String> values)  stateCriteria,required TResult Function( String id,  WorkflowStateKind value)  stateKind,required TResult Function( WorkflowTransition value)  addTransition,required TResult Function( String sourceId,  String targetId)  removeTransition,required TResult Function( String sourceId,  String targetId,  String value)  transitionGuard,required TResult Function( List<WorkflowNodePosition> values)  nodePositions,required TResult Function( WorkflowDefinition value)  enableWorkflow,required TResult Function()  removeWorkflow,}) {final _that = this;
switch (_that) {
case EditModeDisplayName():
return displayName(_that.value);case EditModeDescription():
return description(_that.value);case EditModeOrder():
return orderRaw(_that.value);case EditModePrompt():
return prompt(_that.value);case EditWorkflowTitle():
return workflowTitle(_that.value);case EditWorkflowGoal():
return workflowGoal(_that.value);case EditInitialState():
return initialState(_that.value);case AddWorkflowState():
return addState(_that.value);case RenameWorkflowState():
return renameState(_that.oldId,_that.newId);case RemoveWorkflowState():
return removeState(_that.id);case EditWorkflowStateTitle():
return stateTitle(_that.id,_that.value);case EditWorkflowStateInstructions():
return stateInstructions(_that.id,_that.value);case EditWorkflowStateCriteria():
return stateCriteria(_that.id,_that.values);case EditWorkflowStateKind():
return stateKind(_that.id,_that.value);case AddWorkflowTransition():
return addTransition(_that.value);case RemoveWorkflowTransition():
return removeTransition(_that.sourceId,_that.targetId);case EditWorkflowTransitionGuard():
return transitionGuard(_that.sourceId,_that.targetId,_that.value);case EditWorkflowNodePositions():
return nodePositions(_that.values);case EnableModeWorkflow():
return enableWorkflow(_that.value);case RemoveModeWorkflow():
return removeWorkflow();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String value)?  displayName,TResult? Function( String value)?  description,TResult? Function( String value)?  orderRaw,TResult? Function( String value)?  prompt,TResult? Function( String value)?  workflowTitle,TResult? Function( String value)?  workflowGoal,TResult? Function( String value)?  initialState,TResult? Function( WorkflowState value)?  addState,TResult? Function( String oldId,  String newId)?  renameState,TResult? Function( String id)?  removeState,TResult? Function( String id,  String value)?  stateTitle,TResult? Function( String id,  String value)?  stateInstructions,TResult? Function( String id,  List<String> values)?  stateCriteria,TResult? Function( String id,  WorkflowStateKind value)?  stateKind,TResult? Function( WorkflowTransition value)?  addTransition,TResult? Function( String sourceId,  String targetId)?  removeTransition,TResult? Function( String sourceId,  String targetId,  String value)?  transitionGuard,TResult? Function( List<WorkflowNodePosition> values)?  nodePositions,TResult? Function( WorkflowDefinition value)?  enableWorkflow,TResult? Function()?  removeWorkflow,}) {final _that = this;
switch (_that) {
case EditModeDisplayName() when displayName != null:
return displayName(_that.value);case EditModeDescription() when description != null:
return description(_that.value);case EditModeOrder() when orderRaw != null:
return orderRaw(_that.value);case EditModePrompt() when prompt != null:
return prompt(_that.value);case EditWorkflowTitle() when workflowTitle != null:
return workflowTitle(_that.value);case EditWorkflowGoal() when workflowGoal != null:
return workflowGoal(_that.value);case EditInitialState() when initialState != null:
return initialState(_that.value);case AddWorkflowState() when addState != null:
return addState(_that.value);case RenameWorkflowState() when renameState != null:
return renameState(_that.oldId,_that.newId);case RemoveWorkflowState() when removeState != null:
return removeState(_that.id);case EditWorkflowStateTitle() when stateTitle != null:
return stateTitle(_that.id,_that.value);case EditWorkflowStateInstructions() when stateInstructions != null:
return stateInstructions(_that.id,_that.value);case EditWorkflowStateCriteria() when stateCriteria != null:
return stateCriteria(_that.id,_that.values);case EditWorkflowStateKind() when stateKind != null:
return stateKind(_that.id,_that.value);case AddWorkflowTransition() when addTransition != null:
return addTransition(_that.value);case RemoveWorkflowTransition() when removeTransition != null:
return removeTransition(_that.sourceId,_that.targetId);case EditWorkflowTransitionGuard() when transitionGuard != null:
return transitionGuard(_that.sourceId,_that.targetId,_that.value);case EditWorkflowNodePositions() when nodePositions != null:
return nodePositions(_that.values);case EnableModeWorkflow() when enableWorkflow != null:
return enableWorkflow(_that.value);case RemoveModeWorkflow() when removeWorkflow != null:
return removeWorkflow();case _:
  return null;

}
}

}

/// @nodoc


class EditModeDisplayName implements ModeEdit {
  const EditModeDisplayName(this.value);


 final  String value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditModeDisplayNameCopyWith<EditModeDisplayName> get copyWith => _$EditModeDisplayNameCopyWithImpl<EditModeDisplayName>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditModeDisplayName&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $EditModeDisplayNameCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditModeDisplayNameCopyWith(EditModeDisplayName value, $Res Function(EditModeDisplayName) _then) = _$EditModeDisplayNameCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$EditModeDisplayNameCopyWithImpl<$Res>
    implements $EditModeDisplayNameCopyWith<$Res> {
  _$EditModeDisplayNameCopyWithImpl(this._self, this._then);

  final EditModeDisplayName _self;
  final $Res Function(EditModeDisplayName) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(EditModeDisplayName(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditModeDescription implements ModeEdit {
  const EditModeDescription(this.value);


 final  String value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditModeDescriptionCopyWith<EditModeDescription> get copyWith => _$EditModeDescriptionCopyWithImpl<EditModeDescription>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditModeDescription&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $EditModeDescriptionCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditModeDescriptionCopyWith(EditModeDescription value, $Res Function(EditModeDescription) _then) = _$EditModeDescriptionCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$EditModeDescriptionCopyWithImpl<$Res>
    implements $EditModeDescriptionCopyWith<$Res> {
  _$EditModeDescriptionCopyWithImpl(this._self, this._then);

  final EditModeDescription _self;
  final $Res Function(EditModeDescription) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(EditModeDescription(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditModeOrder implements ModeEdit {
  const EditModeOrder(this.value);


 final  String value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditModeOrderCopyWith<EditModeOrder> get copyWith => _$EditModeOrderCopyWithImpl<EditModeOrder>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditModeOrder&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $EditModeOrderCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditModeOrderCopyWith(EditModeOrder value, $Res Function(EditModeOrder) _then) = _$EditModeOrderCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$EditModeOrderCopyWithImpl<$Res>
    implements $EditModeOrderCopyWith<$Res> {
  _$EditModeOrderCopyWithImpl(this._self, this._then);

  final EditModeOrder _self;
  final $Res Function(EditModeOrder) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(EditModeOrder(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditModePrompt implements ModeEdit {
  const EditModePrompt(this.value);


 final  String value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditModePromptCopyWith<EditModePrompt> get copyWith => _$EditModePromptCopyWithImpl<EditModePrompt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditModePrompt&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $EditModePromptCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditModePromptCopyWith(EditModePrompt value, $Res Function(EditModePrompt) _then) = _$EditModePromptCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$EditModePromptCopyWithImpl<$Res>
    implements $EditModePromptCopyWith<$Res> {
  _$EditModePromptCopyWithImpl(this._self, this._then);

  final EditModePrompt _self;
  final $Res Function(EditModePrompt) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(EditModePrompt(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditWorkflowTitle implements ModeEdit {
  const EditWorkflowTitle(this.value);


 final  String value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditWorkflowTitleCopyWith<EditWorkflowTitle> get copyWith => _$EditWorkflowTitleCopyWithImpl<EditWorkflowTitle>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditWorkflowTitle&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $EditWorkflowTitleCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditWorkflowTitleCopyWith(EditWorkflowTitle value, $Res Function(EditWorkflowTitle) _then) = _$EditWorkflowTitleCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$EditWorkflowTitleCopyWithImpl<$Res>
    implements $EditWorkflowTitleCopyWith<$Res> {
  _$EditWorkflowTitleCopyWithImpl(this._self, this._then);

  final EditWorkflowTitle _self;
  final $Res Function(EditWorkflowTitle) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(EditWorkflowTitle(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditWorkflowGoal implements ModeEdit {
  const EditWorkflowGoal(this.value);


 final  String value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditWorkflowGoalCopyWith<EditWorkflowGoal> get copyWith => _$EditWorkflowGoalCopyWithImpl<EditWorkflowGoal>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditWorkflowGoal&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $EditWorkflowGoalCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditWorkflowGoalCopyWith(EditWorkflowGoal value, $Res Function(EditWorkflowGoal) _then) = _$EditWorkflowGoalCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$EditWorkflowGoalCopyWithImpl<$Res>
    implements $EditWorkflowGoalCopyWith<$Res> {
  _$EditWorkflowGoalCopyWithImpl(this._self, this._then);

  final EditWorkflowGoal _self;
  final $Res Function(EditWorkflowGoal) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(EditWorkflowGoal(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditInitialState implements ModeEdit {
  const EditInitialState(this.value);


 final  String value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditInitialStateCopyWith<EditInitialState> get copyWith => _$EditInitialStateCopyWithImpl<EditInitialState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditInitialState&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $EditInitialStateCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditInitialStateCopyWith(EditInitialState value, $Res Function(EditInitialState) _then) = _$EditInitialStateCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$EditInitialStateCopyWithImpl<$Res>
    implements $EditInitialStateCopyWith<$Res> {
  _$EditInitialStateCopyWithImpl(this._self, this._then);

  final EditInitialState _self;
  final $Res Function(EditInitialState) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(EditInitialState(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AddWorkflowState implements ModeEdit {
  const AddWorkflowState(this.value);


 final  WorkflowState value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddWorkflowStateCopyWith<AddWorkflowState> get copyWith => _$AddWorkflowStateCopyWithImpl<AddWorkflowState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AddWorkflowState&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $AddWorkflowStateCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $AddWorkflowStateCopyWith(AddWorkflowState value, $Res Function(AddWorkflowState) _then) = _$AddWorkflowStateCopyWithImpl;
@useResult
$Res call({
 WorkflowState value
});


$WorkflowStateCopyWith<$Res> get value;

}
/// @nodoc
class _$AddWorkflowStateCopyWithImpl<$Res>
    implements $AddWorkflowStateCopyWith<$Res> {
  _$AddWorkflowStateCopyWithImpl(this._self, this._then);

  final AddWorkflowState _self;
  final $Res Function(AddWorkflowState) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(AddWorkflowState(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as WorkflowState,
  ));
}

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowStateCopyWith<$Res> get value {

  return $WorkflowStateCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class RenameWorkflowState implements ModeEdit {
  const RenameWorkflowState(this.oldId, this.newId);


 final  String oldId;
 final  String newId;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RenameWorkflowStateCopyWith<RenameWorkflowState> get copyWith => _$RenameWorkflowStateCopyWithImpl<RenameWorkflowState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RenameWorkflowState&&(identical(other.oldId, oldId) || other.oldId == oldId)&&(identical(other.newId, newId) || other.newId == newId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,oldId,newId);
}



}

/// @nodoc
abstract mixin class $RenameWorkflowStateCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $RenameWorkflowStateCopyWith(RenameWorkflowState value, $Res Function(RenameWorkflowState) _then) = _$RenameWorkflowStateCopyWithImpl;
@useResult
$Res call({
 String oldId, String newId
});




}
/// @nodoc
class _$RenameWorkflowStateCopyWithImpl<$Res>
    implements $RenameWorkflowStateCopyWith<$Res> {
  _$RenameWorkflowStateCopyWithImpl(this._self, this._then);

  final RenameWorkflowState _self;
  final $Res Function(RenameWorkflowState) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? oldId = null,Object? newId = null,}) {
  return _then(RenameWorkflowState(
null == oldId ? _self.oldId : oldId // ignore: cast_nullable_to_non_nullable
as String,null == newId ? _self.newId : newId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RemoveWorkflowState implements ModeEdit {
  const RemoveWorkflowState(this.id);


 final  String id;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoveWorkflowStateCopyWith<RemoveWorkflowState> get copyWith => _$RemoveWorkflowStateCopyWithImpl<RemoveWorkflowState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveWorkflowState&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id);
}



}

/// @nodoc
abstract mixin class $RemoveWorkflowStateCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $RemoveWorkflowStateCopyWith(RemoveWorkflowState value, $Res Function(RemoveWorkflowState) _then) = _$RemoveWorkflowStateCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$RemoveWorkflowStateCopyWithImpl<$Res>
    implements $RemoveWorkflowStateCopyWith<$Res> {
  _$RemoveWorkflowStateCopyWithImpl(this._self, this._then);

  final RemoveWorkflowState _self;
  final $Res Function(RemoveWorkflowState) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(RemoveWorkflowState(
null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditWorkflowStateTitle implements ModeEdit {
  const EditWorkflowStateTitle(this.id, this.value);


 final  String id;
 final  String value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditWorkflowStateTitleCopyWith<EditWorkflowStateTitle> get copyWith => _$EditWorkflowStateTitleCopyWithImpl<EditWorkflowStateTitle>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditWorkflowStateTitle&&(identical(other.id, id) || other.id == id)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,value);
}



}

/// @nodoc
abstract mixin class $EditWorkflowStateTitleCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditWorkflowStateTitleCopyWith(EditWorkflowStateTitle value, $Res Function(EditWorkflowStateTitle) _then) = _$EditWorkflowStateTitleCopyWithImpl;
@useResult
$Res call({
 String id, String value
});




}
/// @nodoc
class _$EditWorkflowStateTitleCopyWithImpl<$Res>
    implements $EditWorkflowStateTitleCopyWith<$Res> {
  _$EditWorkflowStateTitleCopyWithImpl(this._self, this._then);

  final EditWorkflowStateTitle _self;
  final $Res Function(EditWorkflowStateTitle) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? value = null,}) {
  return _then(EditWorkflowStateTitle(
null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditWorkflowStateInstructions implements ModeEdit {
  const EditWorkflowStateInstructions(this.id, this.value);


 final  String id;
 final  String value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditWorkflowStateInstructionsCopyWith<EditWorkflowStateInstructions> get copyWith => _$EditWorkflowStateInstructionsCopyWithImpl<EditWorkflowStateInstructions>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditWorkflowStateInstructions&&(identical(other.id, id) || other.id == id)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,value);
}



}

/// @nodoc
abstract mixin class $EditWorkflowStateInstructionsCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditWorkflowStateInstructionsCopyWith(EditWorkflowStateInstructions value, $Res Function(EditWorkflowStateInstructions) _then) = _$EditWorkflowStateInstructionsCopyWithImpl;
@useResult
$Res call({
 String id, String value
});




}
/// @nodoc
class _$EditWorkflowStateInstructionsCopyWithImpl<$Res>
    implements $EditWorkflowStateInstructionsCopyWith<$Res> {
  _$EditWorkflowStateInstructionsCopyWithImpl(this._self, this._then);

  final EditWorkflowStateInstructions _self;
  final $Res Function(EditWorkflowStateInstructions) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? value = null,}) {
  return _then(EditWorkflowStateInstructions(
null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditWorkflowStateCriteria implements ModeEdit {
  const EditWorkflowStateCriteria(this.id,  List<String> values): _values = values;


 final  String id;
 final  List<String> _values;
 List<String> get values {
  if (_values is EqualUnmodifiableListView) return _values;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_values);
}


/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditWorkflowStateCriteriaCopyWith<EditWorkflowStateCriteria> get copyWith => _$EditWorkflowStateCriteriaCopyWithImpl<EditWorkflowStateCriteria>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditWorkflowStateCriteria&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.values, _values));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,const DeepCollectionEquality().hash(_values));
}



}

/// @nodoc
abstract mixin class $EditWorkflowStateCriteriaCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditWorkflowStateCriteriaCopyWith(EditWorkflowStateCriteria value, $Res Function(EditWorkflowStateCriteria) _then) = _$EditWorkflowStateCriteriaCopyWithImpl;
@useResult
$Res call({
 String id, List<String> values
});




}
/// @nodoc
class _$EditWorkflowStateCriteriaCopyWithImpl<$Res>
    implements $EditWorkflowStateCriteriaCopyWith<$Res> {
  _$EditWorkflowStateCriteriaCopyWithImpl(this._self, this._then);

  final EditWorkflowStateCriteria _self;
  final $Res Function(EditWorkflowStateCriteria) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? values = null,}) {
  return _then(EditWorkflowStateCriteria(
null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,null == values ? _self._values : values // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class EditWorkflowStateKind implements ModeEdit {
  const EditWorkflowStateKind(this.id, this.value);


 final  String id;
 final  WorkflowStateKind value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditWorkflowStateKindCopyWith<EditWorkflowStateKind> get copyWith => _$EditWorkflowStateKindCopyWithImpl<EditWorkflowStateKind>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditWorkflowStateKind&&(identical(other.id, id) || other.id == id)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,value);
}



}

/// @nodoc
abstract mixin class $EditWorkflowStateKindCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditWorkflowStateKindCopyWith(EditWorkflowStateKind value, $Res Function(EditWorkflowStateKind) _then) = _$EditWorkflowStateKindCopyWithImpl;
@useResult
$Res call({
 String id, WorkflowStateKind value
});




}
/// @nodoc
class _$EditWorkflowStateKindCopyWithImpl<$Res>
    implements $EditWorkflowStateKindCopyWith<$Res> {
  _$EditWorkflowStateKindCopyWithImpl(this._self, this._then);

  final EditWorkflowStateKind _self;
  final $Res Function(EditWorkflowStateKind) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? value = null,}) {
  return _then(EditWorkflowStateKind(
null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as WorkflowStateKind,
  ));
}


}

/// @nodoc


class AddWorkflowTransition implements ModeEdit {
  const AddWorkflowTransition(this.value);


 final  WorkflowTransition value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddWorkflowTransitionCopyWith<AddWorkflowTransition> get copyWith => _$AddWorkflowTransitionCopyWithImpl<AddWorkflowTransition>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AddWorkflowTransition&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $AddWorkflowTransitionCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $AddWorkflowTransitionCopyWith(AddWorkflowTransition value, $Res Function(AddWorkflowTransition) _then) = _$AddWorkflowTransitionCopyWithImpl;
@useResult
$Res call({
 WorkflowTransition value
});


$WorkflowTransitionCopyWith<$Res> get value;

}
/// @nodoc
class _$AddWorkflowTransitionCopyWithImpl<$Res>
    implements $AddWorkflowTransitionCopyWith<$Res> {
  _$AddWorkflowTransitionCopyWithImpl(this._self, this._then);

  final AddWorkflowTransition _self;
  final $Res Function(AddWorkflowTransition) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(AddWorkflowTransition(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as WorkflowTransition,
  ));
}

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowTransitionCopyWith<$Res> get value {

  return $WorkflowTransitionCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class RemoveWorkflowTransition implements ModeEdit {
  const RemoveWorkflowTransition(this.sourceId, this.targetId);


 final  String sourceId;
 final  String targetId;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoveWorkflowTransitionCopyWith<RemoveWorkflowTransition> get copyWith => _$RemoveWorkflowTransitionCopyWithImpl<RemoveWorkflowTransition>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveWorkflowTransition&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.targetId, targetId) || other.targetId == targetId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sourceId,targetId);
}



}

/// @nodoc
abstract mixin class $RemoveWorkflowTransitionCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $RemoveWorkflowTransitionCopyWith(RemoveWorkflowTransition value, $Res Function(RemoveWorkflowTransition) _then) = _$RemoveWorkflowTransitionCopyWithImpl;
@useResult
$Res call({
 String sourceId, String targetId
});




}
/// @nodoc
class _$RemoveWorkflowTransitionCopyWithImpl<$Res>
    implements $RemoveWorkflowTransitionCopyWith<$Res> {
  _$RemoveWorkflowTransitionCopyWithImpl(this._self, this._then);

  final RemoveWorkflowTransition _self;
  final $Res Function(RemoveWorkflowTransition) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sourceId = null,Object? targetId = null,}) {
  return _then(RemoveWorkflowTransition(
null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,null == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditWorkflowTransitionGuard implements ModeEdit {
  const EditWorkflowTransitionGuard(this.sourceId, this.targetId, this.value);


 final  String sourceId;
 final  String targetId;
 final  String value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditWorkflowTransitionGuardCopyWith<EditWorkflowTransitionGuard> get copyWith => _$EditWorkflowTransitionGuardCopyWithImpl<EditWorkflowTransitionGuard>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditWorkflowTransitionGuard&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.targetId, targetId) || other.targetId == targetId)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sourceId,targetId,value);
}



}

/// @nodoc
abstract mixin class $EditWorkflowTransitionGuardCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditWorkflowTransitionGuardCopyWith(EditWorkflowTransitionGuard value, $Res Function(EditWorkflowTransitionGuard) _then) = _$EditWorkflowTransitionGuardCopyWithImpl;
@useResult
$Res call({
 String sourceId, String targetId, String value
});




}
/// @nodoc
class _$EditWorkflowTransitionGuardCopyWithImpl<$Res>
    implements $EditWorkflowTransitionGuardCopyWith<$Res> {
  _$EditWorkflowTransitionGuardCopyWithImpl(this._self, this._then);

  final EditWorkflowTransitionGuard _self;
  final $Res Function(EditWorkflowTransitionGuard) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sourceId = null,Object? targetId = null,Object? value = null,}) {
  return _then(EditWorkflowTransitionGuard(
null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,null == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as String,null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditWorkflowNodePositions implements ModeEdit {
  const EditWorkflowNodePositions( List<WorkflowNodePosition> values): _values = values;


 final  List<WorkflowNodePosition> _values;
 List<WorkflowNodePosition> get values {
  if (_values is EqualUnmodifiableListView) return _values;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_values);
}


/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditWorkflowNodePositionsCopyWith<EditWorkflowNodePositions> get copyWith => _$EditWorkflowNodePositionsCopyWithImpl<EditWorkflowNodePositions>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EditWorkflowNodePositions&&const DeepCollectionEquality().equals(other.values, _values));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_values));
}



}

/// @nodoc
abstract mixin class $EditWorkflowNodePositionsCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EditWorkflowNodePositionsCopyWith(EditWorkflowNodePositions value, $Res Function(EditWorkflowNodePositions) _then) = _$EditWorkflowNodePositionsCopyWithImpl;
@useResult
$Res call({
 List<WorkflowNodePosition> values
});




}
/// @nodoc
class _$EditWorkflowNodePositionsCopyWithImpl<$Res>
    implements $EditWorkflowNodePositionsCopyWith<$Res> {
  _$EditWorkflowNodePositionsCopyWithImpl(this._self, this._then);

  final EditWorkflowNodePositions _self;
  final $Res Function(EditWorkflowNodePositions) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? values = null,}) {
  return _then(EditWorkflowNodePositions(
null == values ? _self._values : values // ignore: cast_nullable_to_non_nullable
as List<WorkflowNodePosition>,
  ));
}


}

/// @nodoc


class EnableModeWorkflow implements ModeEdit {
  const EnableModeWorkflow(this.value);


 final  WorkflowDefinition value;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EnableModeWorkflowCopyWith<EnableModeWorkflow> get copyWith => _$EnableModeWorkflowCopyWithImpl<EnableModeWorkflow>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EnableModeWorkflow&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $EnableModeWorkflowCopyWith<$Res> implements $ModeEditCopyWith<$Res> {
  factory $EnableModeWorkflowCopyWith(EnableModeWorkflow value, $Res Function(EnableModeWorkflow) _then) = _$EnableModeWorkflowCopyWithImpl;
@useResult
$Res call({
 WorkflowDefinition value
});


$WorkflowDefinitionCopyWith<$Res> get value;

}
/// @nodoc
class _$EnableModeWorkflowCopyWithImpl<$Res>
    implements $EnableModeWorkflowCopyWith<$Res> {
  _$EnableModeWorkflowCopyWithImpl(this._self, this._then);

  final EnableModeWorkflow _self;
  final $Res Function(EnableModeWorkflow) _then;

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(EnableModeWorkflow(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as WorkflowDefinition,
  ));
}

/// Create a copy of ModeEdit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowDefinitionCopyWith<$Res> get value {

  return $WorkflowDefinitionCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class RemoveModeWorkflow implements ModeEdit {
  const RemoveModeWorkflow();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveModeWorkflow);
}


@override
int get hashCode => runtimeType.hashCode;



}




// dart format on
