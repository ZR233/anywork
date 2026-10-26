// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mode_documents.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModeDefinition {

 ThreadModeId get id; String get displayName; String get description; int get order; String get prompt; WorkflowDefinition? get workflow;
/// Create a copy of ModeDefinition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeDefinitionCopyWith<ModeDefinition> get copyWith => _$ModeDefinitionCopyWithImpl<ModeDefinition>(this as ModeDefinition, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeDefinition;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeDefinition&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.order, _this.order) || other.order == _this.order)&&(identical(other.prompt, _this.prompt) || other.prompt == _this.prompt)&&(identical(other.workflow, _this.workflow) || other.workflow == _this.workflow));
}


@override
int get hashCode {
  final _this = this as ModeDefinition;
  return Object.hash(runtimeType,_this.id,_this.displayName,_this.description,_this.order,_this.prompt,_this.workflow);
}



}

/// @nodoc
abstract mixin class $ModeDefinitionCopyWith<$Res>  {
  factory $ModeDefinitionCopyWith(ModeDefinition value, $Res Function(ModeDefinition) _then) = _$ModeDefinitionCopyWithImpl;
@useResult
$Res call({
 ThreadModeId id, String displayName, String description, int order, String prompt, WorkflowDefinition? workflow
});


$WorkflowDefinitionCopyWith<$Res>? get workflow;

}
/// @nodoc
class _$ModeDefinitionCopyWithImpl<$Res>
    implements $ModeDefinitionCopyWith<$Res> {
  _$ModeDefinitionCopyWithImpl(this._self, this._then);

  final ModeDefinition _self;
  final $Res Function(ModeDefinition) _then;

/// Create a copy of ModeDefinition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? description = null,Object? order = null,Object? prompt = null,Object? workflow = freezed,}) {
  return _then(ModeDefinition(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ThreadModeId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,workflow: freezed == workflow ? _self.workflow : workflow // ignore: cast_nullable_to_non_nullable
as WorkflowDefinition?,
  ));
}
/// Create a copy of ModeDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowDefinitionCopyWith<$Res>? get workflow {
    if (_self.workflow == null) {
    return null;
  }

  return $WorkflowDefinitionCopyWith<$Res>(_self.workflow!, (value) {
    return _then(_self.copyWith(workflow: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeDefinition].
extension ModeDefinitionPatterns on ModeDefinition {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeDefinition value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeDefinition() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeDefinition value)  $default,){
final _that = this;
switch (_that) {
case _ModeDefinition():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeDefinition value)?  $default,){
final _that = this;
switch (_that) {
case _ModeDefinition() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadModeId id,  String displayName,  String description,  int order,  String prompt,  WorkflowDefinition? workflow)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeDefinition() when $default != null:
return $default(_that.id,_that.displayName,_that.description,_that.order,_that.prompt,_that.workflow);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadModeId id,  String displayName,  String description,  int order,  String prompt,  WorkflowDefinition? workflow)  $default,) {final _that = this;
switch (_that) {
case _ModeDefinition():
return $default(_that.id,_that.displayName,_that.description,_that.order,_that.prompt,_that.workflow);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadModeId id,  String displayName,  String description,  int order,  String prompt,  WorkflowDefinition? workflow)?  $default,) {final _that = this;
switch (_that) {
case _ModeDefinition() when $default != null:
return $default(_that.id,_that.displayName,_that.description,_that.order,_that.prompt,_that.workflow);case _:
  return null;

}
}

}

/// @nodoc


class _ModeDefinition implements ModeDefinition {
  const _ModeDefinition({required this.id, required this.displayName, required this.description, required this.order, required this.prompt, required this.workflow});


@override final  ThreadModeId id;
@override final  String displayName;
@override final  String description;
@override final  int order;
@override final  String prompt;
@override final  WorkflowDefinition? workflow;

/// Create a copy of ModeDefinition
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeDefinitionCopyWith<_ModeDefinition> get copyWith => __$ModeDefinitionCopyWithImpl<_ModeDefinition>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeDefinition&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.order, order) || other.order == order)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.workflow, workflow) || other.workflow == workflow));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName,description,order,prompt,workflow);
}



}

/// @nodoc
abstract mixin class _$ModeDefinitionCopyWith<$Res> implements $ModeDefinitionCopyWith<$Res> {
  factory _$ModeDefinitionCopyWith(_ModeDefinition value, $Res Function(_ModeDefinition) _then) = __$ModeDefinitionCopyWithImpl;
@override @useResult
$Res call({
 ThreadModeId id, String displayName, String description, int order, String prompt, WorkflowDefinition? workflow
});


@override $WorkflowDefinitionCopyWith<$Res>? get workflow;

}
/// @nodoc
class __$ModeDefinitionCopyWithImpl<$Res>
    implements _$ModeDefinitionCopyWith<$Res> {
  __$ModeDefinitionCopyWithImpl(this._self, this._then);

  final _ModeDefinition _self;
  final $Res Function(_ModeDefinition) _then;

/// Create a copy of ModeDefinition
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? description = null,Object? order = null,Object? prompt = null,Object? workflow = freezed,}) {
  return _then(_ModeDefinition(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ThreadModeId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,workflow: freezed == workflow ? _self.workflow : workflow // ignore: cast_nullable_to_non_nullable
as WorkflowDefinition?,
  ));
}

/// Create a copy of ModeDefinition
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowDefinitionCopyWith<$Res>? get workflow {
    if (_self.workflow == null) {
    return null;
  }

  return $WorkflowDefinitionCopyWith<$Res>(_self.workflow!, (value) {
    return _then(_self.copyWith(workflow: value));
  });
}
}

/// @nodoc
mixin _$ModeDocument {

 ModeDefinition get definition; ModeEditorLayout get editor;
/// Create a copy of ModeDocument
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeDocumentCopyWith<ModeDocument> get copyWith => _$ModeDocumentCopyWithImpl<ModeDocument>(this as ModeDocument, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeDocument;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeDocument&&(identical(other.definition, _this.definition) || other.definition == _this.definition)&&(identical(other.editor, _this.editor) || other.editor == _this.editor));
}


@override
int get hashCode {
  final _this = this as ModeDocument;
  return Object.hash(runtimeType,_this.definition,_this.editor);
}



}

/// @nodoc
abstract mixin class $ModeDocumentCopyWith<$Res>  {
  factory $ModeDocumentCopyWith(ModeDocument value, $Res Function(ModeDocument) _then) = _$ModeDocumentCopyWithImpl;
@useResult
$Res call({
 ModeDefinition definition, ModeEditorLayout editor
});


$ModeDefinitionCopyWith<$Res> get definition;$ModeEditorLayoutCopyWith<$Res> get editor;

}
/// @nodoc
class _$ModeDocumentCopyWithImpl<$Res>
    implements $ModeDocumentCopyWith<$Res> {
  _$ModeDocumentCopyWithImpl(this._self, this._then);

  final ModeDocument _self;
  final $Res Function(ModeDocument) _then;

/// Create a copy of ModeDocument
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? definition = null,Object? editor = null,}) {
  return _then(ModeDocument(
definition: null == definition ? _self.definition : definition // ignore: cast_nullable_to_non_nullable
as ModeDefinition,editor: null == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as ModeEditorLayout,
  ));
}
/// Create a copy of ModeDocument
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDefinitionCopyWith<$Res> get definition {

  return $ModeDefinitionCopyWith<$Res>(_self.definition, (value) {
    return _then(_self.copyWith(definition: value));
  });
}/// Create a copy of ModeDocument
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeEditorLayoutCopyWith<$Res> get editor {

  return $ModeEditorLayoutCopyWith<$Res>(_self.editor, (value) {
    return _then(_self.copyWith(editor: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeDocument].
extension ModeDocumentPatterns on ModeDocument {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeDocument value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeDocument() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeDocument value)  $default,){
final _that = this;
switch (_that) {
case _ModeDocument():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeDocument value)?  $default,){
final _that = this;
switch (_that) {
case _ModeDocument() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModeDefinition definition,  ModeEditorLayout editor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeDocument() when $default != null:
return $default(_that.definition,_that.editor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModeDefinition definition,  ModeEditorLayout editor)  $default,) {final _that = this;
switch (_that) {
case _ModeDocument():
return $default(_that.definition,_that.editor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModeDefinition definition,  ModeEditorLayout editor)?  $default,) {final _that = this;
switch (_that) {
case _ModeDocument() when $default != null:
return $default(_that.definition,_that.editor);case _:
  return null;

}
}

}

/// @nodoc


class _ModeDocument extends ModeDocument {
  const _ModeDocument({required this.definition, required this.editor}): super._();


@override final  ModeDefinition definition;
@override final  ModeEditorLayout editor;

/// Create a copy of ModeDocument
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeDocumentCopyWith<_ModeDocument> get copyWith => __$ModeDocumentCopyWithImpl<_ModeDocument>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeDocument&&(identical(other.definition, definition) || other.definition == definition)&&(identical(other.editor, editor) || other.editor == editor));
}


@override
int get hashCode {
    return Object.hash(runtimeType,definition,editor);
}



}

/// @nodoc
abstract mixin class _$ModeDocumentCopyWith<$Res> implements $ModeDocumentCopyWith<$Res> {
  factory _$ModeDocumentCopyWith(_ModeDocument value, $Res Function(_ModeDocument) _then) = __$ModeDocumentCopyWithImpl;
@override @useResult
$Res call({
 ModeDefinition definition, ModeEditorLayout editor
});


@override $ModeDefinitionCopyWith<$Res> get definition;@override $ModeEditorLayoutCopyWith<$Res> get editor;

}
/// @nodoc
class __$ModeDocumentCopyWithImpl<$Res>
    implements _$ModeDocumentCopyWith<$Res> {
  __$ModeDocumentCopyWithImpl(this._self, this._then);

  final _ModeDocument _self;
  final $Res Function(_ModeDocument) _then;

/// Create a copy of ModeDocument
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? definition = null,Object? editor = null,}) {
  return _then(_ModeDocument(
definition: null == definition ? _self.definition : definition // ignore: cast_nullable_to_non_nullable
as ModeDefinition,editor: null == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as ModeEditorLayout,
  ));
}

/// Create a copy of ModeDocument
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDefinitionCopyWith<$Res> get definition {

  return $ModeDefinitionCopyWith<$Res>(_self.definition, (value) {
    return _then(_self.copyWith(definition: value));
  });
}/// Create a copy of ModeDocument
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeEditorLayoutCopyWith<$Res> get editor {

  return $ModeEditorLayoutCopyWith<$Res>(_self.editor, (value) {
    return _then(_self.copyWith(editor: value));
  });
}
}

/// @nodoc
mixin _$ModeEditorLayout {

 List<WorkflowNodePosition> get nodes;
/// Create a copy of ModeEditorLayout
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeEditorLayoutCopyWith<ModeEditorLayout> get copyWith => _$ModeEditorLayoutCopyWithImpl<ModeEditorLayout>(this as ModeEditorLayout, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeEditorLayout;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeEditorLayout&&const DeepCollectionEquality().equals(other.nodes, _this.nodes));
}


@override
int get hashCode {
  final _this = this as ModeEditorLayout;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.nodes));
}

@override
String toString() {
  final _this = this as ModeEditorLayout;
  return 'ModeEditorLayout(nodes: ${_this.nodes})';
}


}

/// @nodoc
abstract mixin class $ModeEditorLayoutCopyWith<$Res>  {
  factory $ModeEditorLayoutCopyWith(ModeEditorLayout value, $Res Function(ModeEditorLayout) _then) = _$ModeEditorLayoutCopyWithImpl;
@useResult
$Res call({
 List<WorkflowNodePosition> nodes
});




}
/// @nodoc
class _$ModeEditorLayoutCopyWithImpl<$Res>
    implements $ModeEditorLayoutCopyWith<$Res> {
  _$ModeEditorLayoutCopyWithImpl(this._self, this._then);

  final ModeEditorLayout _self;
  final $Res Function(ModeEditorLayout) _then;

/// Create a copy of ModeEditorLayout
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? nodes = null,}) {
  return _then(ModeEditorLayout(
nodes: null == nodes ? _self.nodes : nodes // ignore: cast_nullable_to_non_nullable
as List<WorkflowNodePosition>,
  ));
}

}


/// Adds pattern-matching-related methods to [ModeEditorLayout].
extension ModeEditorLayoutPatterns on ModeEditorLayout {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeEditorLayout value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeEditorLayout() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeEditorLayout value)  $default,){
final _that = this;
switch (_that) {
case _ModeEditorLayout():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeEditorLayout value)?  $default,){
final _that = this;
switch (_that) {
case _ModeEditorLayout() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<WorkflowNodePosition> nodes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeEditorLayout() when $default != null:
return $default(_that.nodes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<WorkflowNodePosition> nodes)  $default,) {final _that = this;
switch (_that) {
case _ModeEditorLayout():
return $default(_that.nodes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<WorkflowNodePosition> nodes)?  $default,) {final _that = this;
switch (_that) {
case _ModeEditorLayout() when $default != null:
return $default(_that.nodes);case _:
  return null;

}
}

}

/// @nodoc


class _ModeEditorLayout implements ModeEditorLayout {
  const _ModeEditorLayout({required  List<WorkflowNodePosition> nodes}): _nodes = nodes;


 final  List<WorkflowNodePosition> _nodes;
@override List<WorkflowNodePosition> get nodes {
  if (_nodes is EqualUnmodifiableListView) return _nodes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_nodes);
}


/// Create a copy of ModeEditorLayout
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeEditorLayoutCopyWith<_ModeEditorLayout> get copyWith => __$ModeEditorLayoutCopyWithImpl<_ModeEditorLayout>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeEditorLayout&&const DeepCollectionEquality().equals(other.nodes, _nodes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_nodes));
}

@override
String toString() {
    return 'ModeEditorLayout(nodes: $nodes)';
}


}

/// @nodoc
abstract mixin class _$ModeEditorLayoutCopyWith<$Res> implements $ModeEditorLayoutCopyWith<$Res> {
  factory _$ModeEditorLayoutCopyWith(_ModeEditorLayout value, $Res Function(_ModeEditorLayout) _then) = __$ModeEditorLayoutCopyWithImpl;
@override @useResult
$Res call({
 List<WorkflowNodePosition> nodes
});




}
/// @nodoc
class __$ModeEditorLayoutCopyWithImpl<$Res>
    implements _$ModeEditorLayoutCopyWith<$Res> {
  __$ModeEditorLayoutCopyWithImpl(this._self, this._then);

  final _ModeEditorLayout _self;
  final $Res Function(_ModeEditorLayout) _then;

/// Create a copy of ModeEditorLayout
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodes = null,}) {
  return _then(_ModeEditorLayout(
nodes: null == nodes ? _self._nodes : nodes // ignore: cast_nullable_to_non_nullable
as List<WorkflowNodePosition>,
  ));
}


}

/// @nodoc
mixin _$WorkflowNodePosition {

 String get stateId; double get x; double get y;
/// Create a copy of WorkflowNodePosition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowNodePositionCopyWith<WorkflowNodePosition> get copyWith => _$WorkflowNodePositionCopyWithImpl<WorkflowNodePosition>(this as WorkflowNodePosition, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkflowNodePosition;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowNodePosition&&(identical(other.stateId, _this.stateId) || other.stateId == _this.stateId)&&(identical(other.x, _this.x) || other.x == _this.x)&&(identical(other.y, _this.y) || other.y == _this.y));
}


@override
int get hashCode {
  final _this = this as WorkflowNodePosition;
  return Object.hash(runtimeType,_this.stateId,_this.x,_this.y);
}

@override
String toString() {
  final _this = this as WorkflowNodePosition;
  return 'WorkflowNodePosition(stateId: ${_this.stateId}, x: ${_this.x}, y: ${_this.y})';
}


}

/// @nodoc
abstract mixin class $WorkflowNodePositionCopyWith<$Res>  {
  factory $WorkflowNodePositionCopyWith(WorkflowNodePosition value, $Res Function(WorkflowNodePosition) _then) = _$WorkflowNodePositionCopyWithImpl;
@useResult
$Res call({
 String stateId, double x, double y
});




}
/// @nodoc
class _$WorkflowNodePositionCopyWithImpl<$Res>
    implements $WorkflowNodePositionCopyWith<$Res> {
  _$WorkflowNodePositionCopyWithImpl(this._self, this._then);

  final WorkflowNodePosition _self;
  final $Res Function(WorkflowNodePosition) _then;

/// Create a copy of WorkflowNodePosition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stateId = null,Object? x = null,Object? y = null,}) {
  return _then(WorkflowNodePosition(
stateId: null == stateId ? _self.stateId : stateId // ignore: cast_nullable_to_non_nullable
as String,x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkflowNodePosition].
extension WorkflowNodePositionPatterns on WorkflowNodePosition {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowNodePosition value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowNodePosition() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowNodePosition value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowNodePosition():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowNodePosition value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowNodePosition() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String stateId,  double x,  double y)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowNodePosition() when $default != null:
return $default(_that.stateId,_that.x,_that.y);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String stateId,  double x,  double y)  $default,) {final _that = this;
switch (_that) {
case _WorkflowNodePosition():
return $default(_that.stateId,_that.x,_that.y);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String stateId,  double x,  double y)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowNodePosition() when $default != null:
return $default(_that.stateId,_that.x,_that.y);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowNodePosition implements WorkflowNodePosition {
  const _WorkflowNodePosition({required this.stateId, required this.x, required this.y});


@override final  String stateId;
@override final  double x;
@override final  double y;

/// Create a copy of WorkflowNodePosition
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowNodePositionCopyWith<_WorkflowNodePosition> get copyWith => __$WorkflowNodePositionCopyWithImpl<_WorkflowNodePosition>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowNodePosition&&(identical(other.stateId, stateId) || other.stateId == stateId)&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stateId,x,y);
}

@override
String toString() {
    return 'WorkflowNodePosition(stateId: $stateId, x: $x, y: $y)';
}


}

/// @nodoc
abstract mixin class _$WorkflowNodePositionCopyWith<$Res> implements $WorkflowNodePositionCopyWith<$Res> {
  factory _$WorkflowNodePositionCopyWith(_WorkflowNodePosition value, $Res Function(_WorkflowNodePosition) _then) = __$WorkflowNodePositionCopyWithImpl;
@override @useResult
$Res call({
 String stateId, double x, double y
});




}
/// @nodoc
class __$WorkflowNodePositionCopyWithImpl<$Res>
    implements _$WorkflowNodePositionCopyWith<$Res> {
  __$WorkflowNodePositionCopyWithImpl(this._self, this._then);

  final _WorkflowNodePosition _self;
  final $Res Function(_WorkflowNodePosition) _then;

/// Create a copy of WorkflowNodePosition
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stateId = null,Object? x = null,Object? y = null,}) {
  return _then(_WorkflowNodePosition(
stateId: null == stateId ? _self.stateId : stateId // ignore: cast_nullable_to_non_nullable
as String,x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc
mixin _$WorkflowDefinition {

 String get title; String get goal; String get initialStateId; List<WorkflowState> get states; List<WorkflowTransition> get transitions;
/// Create a copy of WorkflowDefinition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowDefinitionCopyWith<WorkflowDefinition> get copyWith => _$WorkflowDefinitionCopyWithImpl<WorkflowDefinition>(this as WorkflowDefinition, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkflowDefinition;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowDefinition&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.goal, _this.goal) || other.goal == _this.goal)&&(identical(other.initialStateId, _this.initialStateId) || other.initialStateId == _this.initialStateId)&&const DeepCollectionEquality().equals(other.states, _this.states)&&const DeepCollectionEquality().equals(other.transitions, _this.transitions));
}


@override
int get hashCode {
  final _this = this as WorkflowDefinition;
  return Object.hash(runtimeType,_this.title,_this.goal,_this.initialStateId,const DeepCollectionEquality().hash(_this.states),const DeepCollectionEquality().hash(_this.transitions));
}



}

/// @nodoc
abstract mixin class $WorkflowDefinitionCopyWith<$Res>  {
  factory $WorkflowDefinitionCopyWith(WorkflowDefinition value, $Res Function(WorkflowDefinition) _then) = _$WorkflowDefinitionCopyWithImpl;
@useResult
$Res call({
 String title, String goal, String initialStateId, List<WorkflowState> states, List<WorkflowTransition> transitions
});




}
/// @nodoc
class _$WorkflowDefinitionCopyWithImpl<$Res>
    implements $WorkflowDefinitionCopyWith<$Res> {
  _$WorkflowDefinitionCopyWithImpl(this._self, this._then);

  final WorkflowDefinition _self;
  final $Res Function(WorkflowDefinition) _then;

/// Create a copy of WorkflowDefinition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? goal = null,Object? initialStateId = null,Object? states = null,Object? transitions = null,}) {
  return _then(WorkflowDefinition(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,goal: null == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as String,initialStateId: null == initialStateId ? _self.initialStateId : initialStateId // ignore: cast_nullable_to_non_nullable
as String,states: null == states ? _self.states : states // ignore: cast_nullable_to_non_nullable
as List<WorkflowState>,transitions: null == transitions ? _self.transitions : transitions // ignore: cast_nullable_to_non_nullable
as List<WorkflowTransition>,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkflowDefinition].
extension WorkflowDefinitionPatterns on WorkflowDefinition {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowDefinition value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowDefinition() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowDefinition value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowDefinition():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowDefinition value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowDefinition() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String title,  String goal,  String initialStateId,  List<WorkflowState> states,  List<WorkflowTransition> transitions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowDefinition() when $default != null:
return $default(_that.title,_that.goal,_that.initialStateId,_that.states,_that.transitions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String title,  String goal,  String initialStateId,  List<WorkflowState> states,  List<WorkflowTransition> transitions)  $default,) {final _that = this;
switch (_that) {
case _WorkflowDefinition():
return $default(_that.title,_that.goal,_that.initialStateId,_that.states,_that.transitions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String title,  String goal,  String initialStateId,  List<WorkflowState> states,  List<WorkflowTransition> transitions)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowDefinition() when $default != null:
return $default(_that.title,_that.goal,_that.initialStateId,_that.states,_that.transitions);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowDefinition extends WorkflowDefinition {
  const _WorkflowDefinition({required this.title, required this.goal, required this.initialStateId, required  List<WorkflowState> states, required  List<WorkflowTransition> transitions}): _states = states,_transitions = transitions,super._();


@override final  String title;
@override final  String goal;
@override final  String initialStateId;
 final  List<WorkflowState> _states;
@override List<WorkflowState> get states {
  if (_states is EqualUnmodifiableListView) return _states;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_states);
}

 final  List<WorkflowTransition> _transitions;
@override List<WorkflowTransition> get transitions {
  if (_transitions is EqualUnmodifiableListView) return _transitions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_transitions);
}


/// Create a copy of WorkflowDefinition
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowDefinitionCopyWith<_WorkflowDefinition> get copyWith => __$WorkflowDefinitionCopyWithImpl<_WorkflowDefinition>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowDefinition&&(identical(other.title, title) || other.title == title)&&(identical(other.goal, goal) || other.goal == goal)&&(identical(other.initialStateId, initialStateId) || other.initialStateId == initialStateId)&&const DeepCollectionEquality().equals(other.states, _states)&&const DeepCollectionEquality().equals(other.transitions, _transitions));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,goal,initialStateId,const DeepCollectionEquality().hash(_states),const DeepCollectionEquality().hash(_transitions));
}



}

/// @nodoc
abstract mixin class _$WorkflowDefinitionCopyWith<$Res> implements $WorkflowDefinitionCopyWith<$Res> {
  factory _$WorkflowDefinitionCopyWith(_WorkflowDefinition value, $Res Function(_WorkflowDefinition) _then) = __$WorkflowDefinitionCopyWithImpl;
@override @useResult
$Res call({
 String title, String goal, String initialStateId, List<WorkflowState> states, List<WorkflowTransition> transitions
});




}
/// @nodoc
class __$WorkflowDefinitionCopyWithImpl<$Res>
    implements _$WorkflowDefinitionCopyWith<$Res> {
  __$WorkflowDefinitionCopyWithImpl(this._self, this._then);

  final _WorkflowDefinition _self;
  final $Res Function(_WorkflowDefinition) _then;

/// Create a copy of WorkflowDefinition
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? goal = null,Object? initialStateId = null,Object? states = null,Object? transitions = null,}) {
  return _then(_WorkflowDefinition(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,goal: null == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as String,initialStateId: null == initialStateId ? _self.initialStateId : initialStateId // ignore: cast_nullable_to_non_nullable
as String,states: null == states ? _self._states : states // ignore: cast_nullable_to_non_nullable
as List<WorkflowState>,transitions: null == transitions ? _self._transitions : transitions // ignore: cast_nullable_to_non_nullable
as List<WorkflowTransition>,
  ));
}


}

/// @nodoc
mixin _$WorkflowState {

 String get id; String get title; String get instructions; List<String> get completionCriteria; WorkflowStateKind get kind;
/// Create a copy of WorkflowState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowStateCopyWith<WorkflowState> get copyWith => _$WorkflowStateCopyWithImpl<WorkflowState>(this as WorkflowState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkflowState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowState&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.instructions, _this.instructions) || other.instructions == _this.instructions)&&const DeepCollectionEquality().equals(other.completionCriteria, _this.completionCriteria)&&(identical(other.kind, _this.kind) || other.kind == _this.kind));
}


@override
int get hashCode {
  final _this = this as WorkflowState;
  return Object.hash(runtimeType,_this.id,_this.title,_this.instructions,const DeepCollectionEquality().hash(_this.completionCriteria),_this.kind);
}



}

/// @nodoc
abstract mixin class $WorkflowStateCopyWith<$Res>  {
  factory $WorkflowStateCopyWith(WorkflowState value, $Res Function(WorkflowState) _then) = _$WorkflowStateCopyWithImpl;
@useResult
$Res call({
 String id, String title, String instructions, List<String> completionCriteria, WorkflowStateKind kind
});




}
/// @nodoc
class _$WorkflowStateCopyWithImpl<$Res>
    implements $WorkflowStateCopyWith<$Res> {
  _$WorkflowStateCopyWithImpl(this._self, this._then);

  final WorkflowState _self;
  final $Res Function(WorkflowState) _then;

/// Create a copy of WorkflowState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? instructions = null,Object? completionCriteria = null,Object? kind = null,}) {
  return _then(WorkflowState(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,instructions: null == instructions ? _self.instructions : instructions // ignore: cast_nullable_to_non_nullable
as String,completionCriteria: null == completionCriteria ? _self.completionCriteria : completionCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as WorkflowStateKind,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkflowState].
extension WorkflowStatePatterns on WorkflowState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowState value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowState value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String instructions,  List<String> completionCriteria,  WorkflowStateKind kind)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowState() when $default != null:
return $default(_that.id,_that.title,_that.instructions,_that.completionCriteria,_that.kind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String instructions,  List<String> completionCriteria,  WorkflowStateKind kind)  $default,) {final _that = this;
switch (_that) {
case _WorkflowState():
return $default(_that.id,_that.title,_that.instructions,_that.completionCriteria,_that.kind);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String instructions,  List<String> completionCriteria,  WorkflowStateKind kind)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowState() when $default != null:
return $default(_that.id,_that.title,_that.instructions,_that.completionCriteria,_that.kind);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowState extends WorkflowState {
  const _WorkflowState({required this.id, required this.title, required this.instructions, required  List<String> completionCriteria, required this.kind}): _completionCriteria = completionCriteria,super._();


@override final  String id;
@override final  String title;
@override final  String instructions;
 final  List<String> _completionCriteria;
@override List<String> get completionCriteria {
  if (_completionCriteria is EqualUnmodifiableListView) return _completionCriteria;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_completionCriteria);
}

@override final  WorkflowStateKind kind;

/// Create a copy of WorkflowState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowStateCopyWith<_WorkflowState> get copyWith => __$WorkflowStateCopyWithImpl<_WorkflowState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowState&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.instructions, instructions) || other.instructions == instructions)&&const DeepCollectionEquality().equals(other.completionCriteria, _completionCriteria)&&(identical(other.kind, kind) || other.kind == kind));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,title,instructions,const DeepCollectionEquality().hash(_completionCriteria),kind);
}



}

/// @nodoc
abstract mixin class _$WorkflowStateCopyWith<$Res> implements $WorkflowStateCopyWith<$Res> {
  factory _$WorkflowStateCopyWith(_WorkflowState value, $Res Function(_WorkflowState) _then) = __$WorkflowStateCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String instructions, List<String> completionCriteria, WorkflowStateKind kind
});




}
/// @nodoc
class __$WorkflowStateCopyWithImpl<$Res>
    implements _$WorkflowStateCopyWith<$Res> {
  __$WorkflowStateCopyWithImpl(this._self, this._then);

  final _WorkflowState _self;
  final $Res Function(_WorkflowState) _then;

/// Create a copy of WorkflowState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? instructions = null,Object? completionCriteria = null,Object? kind = null,}) {
  return _then(_WorkflowState(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,instructions: null == instructions ? _self.instructions : instructions // ignore: cast_nullable_to_non_nullable
as String,completionCriteria: null == completionCriteria ? _self._completionCriteria : completionCriteria // ignore: cast_nullable_to_non_nullable
as List<String>,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as WorkflowStateKind,
  ));
}


}

/// @nodoc
mixin _$WorkflowTransition {

 String get sourceStateId; String get targetStateId; String get guard;
/// Create a copy of WorkflowTransition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowTransitionCopyWith<WorkflowTransition> get copyWith => _$WorkflowTransitionCopyWithImpl<WorkflowTransition>(this as WorkflowTransition, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkflowTransition;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowTransition&&(identical(other.sourceStateId, _this.sourceStateId) || other.sourceStateId == _this.sourceStateId)&&(identical(other.targetStateId, _this.targetStateId) || other.targetStateId == _this.targetStateId)&&(identical(other.guard, _this.guard) || other.guard == _this.guard));
}


@override
int get hashCode {
  final _this = this as WorkflowTransition;
  return Object.hash(runtimeType,_this.sourceStateId,_this.targetStateId,_this.guard);
}



}

/// @nodoc
abstract mixin class $WorkflowTransitionCopyWith<$Res>  {
  factory $WorkflowTransitionCopyWith(WorkflowTransition value, $Res Function(WorkflowTransition) _then) = _$WorkflowTransitionCopyWithImpl;
@useResult
$Res call({
 String sourceStateId, String targetStateId, String guard
});




}
/// @nodoc
class _$WorkflowTransitionCopyWithImpl<$Res>
    implements $WorkflowTransitionCopyWith<$Res> {
  _$WorkflowTransitionCopyWithImpl(this._self, this._then);

  final WorkflowTransition _self;
  final $Res Function(WorkflowTransition) _then;

/// Create a copy of WorkflowTransition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sourceStateId = null,Object? targetStateId = null,Object? guard = null,}) {
  return _then(WorkflowTransition(
sourceStateId: null == sourceStateId ? _self.sourceStateId : sourceStateId // ignore: cast_nullable_to_non_nullable
as String,targetStateId: null == targetStateId ? _self.targetStateId : targetStateId // ignore: cast_nullable_to_non_nullable
as String,guard: null == guard ? _self.guard : guard // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkflowTransition].
extension WorkflowTransitionPatterns on WorkflowTransition {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowTransition value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowTransition() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowTransition value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowTransition():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowTransition value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowTransition() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sourceStateId,  String targetStateId,  String guard)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowTransition() when $default != null:
return $default(_that.sourceStateId,_that.targetStateId,_that.guard);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sourceStateId,  String targetStateId,  String guard)  $default,) {final _that = this;
switch (_that) {
case _WorkflowTransition():
return $default(_that.sourceStateId,_that.targetStateId,_that.guard);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sourceStateId,  String targetStateId,  String guard)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowTransition() when $default != null:
return $default(_that.sourceStateId,_that.targetStateId,_that.guard);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowTransition extends WorkflowTransition {
  const _WorkflowTransition({required this.sourceStateId, required this.targetStateId, required this.guard}): super._();


@override final  String sourceStateId;
@override final  String targetStateId;
@override final  String guard;

/// Create a copy of WorkflowTransition
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowTransitionCopyWith<_WorkflowTransition> get copyWith => __$WorkflowTransitionCopyWithImpl<_WorkflowTransition>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowTransition&&(identical(other.sourceStateId, sourceStateId) || other.sourceStateId == sourceStateId)&&(identical(other.targetStateId, targetStateId) || other.targetStateId == targetStateId)&&(identical(other.guard, guard) || other.guard == guard));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sourceStateId,targetStateId,guard);
}



}

/// @nodoc
abstract mixin class _$WorkflowTransitionCopyWith<$Res> implements $WorkflowTransitionCopyWith<$Res> {
  factory _$WorkflowTransitionCopyWith(_WorkflowTransition value, $Res Function(_WorkflowTransition) _then) = __$WorkflowTransitionCopyWithImpl;
@override @useResult
$Res call({
 String sourceStateId, String targetStateId, String guard
});




}
/// @nodoc
class __$WorkflowTransitionCopyWithImpl<$Res>
    implements _$WorkflowTransitionCopyWith<$Res> {
  __$WorkflowTransitionCopyWithImpl(this._self, this._then);

  final _WorkflowTransition _self;
  final $Res Function(_WorkflowTransition) _then;

/// Create a copy of WorkflowTransition
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourceStateId = null,Object? targetStateId = null,Object? guard = null,}) {
  return _then(_WorkflowTransition(
sourceStateId: null == sourceStateId ? _self.sourceStateId : sourceStateId // ignore: cast_nullable_to_non_nullable
as String,targetStateId: null == targetStateId ? _self.targetStateId : targetStateId // ignore: cast_nullable_to_non_nullable
as String,guard: null == guard ? _self.guard : guard // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ModeDefinitionSnapshot {

 int get revision; ModeDocument get document; bool get readOnly;
/// Create a copy of ModeDefinitionSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeDefinitionSnapshotCopyWith<ModeDefinitionSnapshot> get copyWith => _$ModeDefinitionSnapshotCopyWithImpl<ModeDefinitionSnapshot>(this as ModeDefinitionSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeDefinitionSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeDefinitionSnapshot&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.document, _this.document) || other.document == _this.document)&&(identical(other.readOnly, _this.readOnly) || other.readOnly == _this.readOnly));
}


@override
int get hashCode {
  final _this = this as ModeDefinitionSnapshot;
  return Object.hash(runtimeType,_this.revision,_this.document,_this.readOnly);
}



}

/// @nodoc
abstract mixin class $ModeDefinitionSnapshotCopyWith<$Res>  {
  factory $ModeDefinitionSnapshotCopyWith(ModeDefinitionSnapshot value, $Res Function(ModeDefinitionSnapshot) _then) = _$ModeDefinitionSnapshotCopyWithImpl;
@useResult
$Res call({
 int revision, ModeDocument document, bool readOnly
});


$ModeDocumentCopyWith<$Res> get document;

}
/// @nodoc
class _$ModeDefinitionSnapshotCopyWithImpl<$Res>
    implements $ModeDefinitionSnapshotCopyWith<$Res> {
  _$ModeDefinitionSnapshotCopyWithImpl(this._self, this._then);

  final ModeDefinitionSnapshot _self;
  final $Res Function(ModeDefinitionSnapshot) _then;

/// Create a copy of ModeDefinitionSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? document = null,Object? readOnly = null,}) {
  return _then(ModeDefinitionSnapshot(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,document: null == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as ModeDocument,readOnly: null == readOnly ? _self.readOnly : readOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ModeDefinitionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDocumentCopyWith<$Res> get document {

  return $ModeDocumentCopyWith<$Res>(_self.document, (value) {
    return _then(_self.copyWith(document: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeDefinitionSnapshot].
extension ModeDefinitionSnapshotPatterns on ModeDefinitionSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeDefinitionSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeDefinitionSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeDefinitionSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _ModeDefinitionSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeDefinitionSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _ModeDefinitionSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  ModeDocument document,  bool readOnly)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeDefinitionSnapshot() when $default != null:
return $default(_that.revision,_that.document,_that.readOnly);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  ModeDocument document,  bool readOnly)  $default,) {final _that = this;
switch (_that) {
case _ModeDefinitionSnapshot():
return $default(_that.revision,_that.document,_that.readOnly);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  ModeDocument document,  bool readOnly)?  $default,) {final _that = this;
switch (_that) {
case _ModeDefinitionSnapshot() when $default != null:
return $default(_that.revision,_that.document,_that.readOnly);case _:
  return null;

}
}

}

/// @nodoc


class _ModeDefinitionSnapshot implements ModeDefinitionSnapshot {
  const _ModeDefinitionSnapshot({required this.revision, required this.document, required this.readOnly});


@override final  int revision;
@override final  ModeDocument document;
@override final  bool readOnly;

/// Create a copy of ModeDefinitionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeDefinitionSnapshotCopyWith<_ModeDefinitionSnapshot> get copyWith => __$ModeDefinitionSnapshotCopyWithImpl<_ModeDefinitionSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeDefinitionSnapshot&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.document, document) || other.document == document)&&(identical(other.readOnly, readOnly) || other.readOnly == readOnly));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,document,readOnly);
}



}

/// @nodoc
abstract mixin class _$ModeDefinitionSnapshotCopyWith<$Res> implements $ModeDefinitionSnapshotCopyWith<$Res> {
  factory _$ModeDefinitionSnapshotCopyWith(_ModeDefinitionSnapshot value, $Res Function(_ModeDefinitionSnapshot) _then) = __$ModeDefinitionSnapshotCopyWithImpl;
@override @useResult
$Res call({
 int revision, ModeDocument document, bool readOnly
});


@override $ModeDocumentCopyWith<$Res> get document;

}
/// @nodoc
class __$ModeDefinitionSnapshotCopyWithImpl<$Res>
    implements _$ModeDefinitionSnapshotCopyWith<$Res> {
  __$ModeDefinitionSnapshotCopyWithImpl(this._self, this._then);

  final _ModeDefinitionSnapshot _self;
  final $Res Function(_ModeDefinitionSnapshot) _then;

/// Create a copy of ModeDefinitionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? document = null,Object? readOnly = null,}) {
  return _then(_ModeDefinitionSnapshot(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,document: null == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as ModeDocument,readOnly: null == readOnly ? _self.readOnly : readOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ModeDefinitionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDocumentCopyWith<$Res> get document {

  return $ModeDocumentCopyWith<$Res>(_self.document, (value) {
    return _then(_self.copyWith(document: value));
  });
}
}

/// @nodoc
mixin _$ModeValidationResult {

 ModeDocument? get document; List<ValidationIssue> get issues;
/// Create a copy of ModeValidationResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeValidationResultCopyWith<ModeValidationResult> get copyWith => _$ModeValidationResultCopyWithImpl<ModeValidationResult>(this as ModeValidationResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeValidationResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeValidationResult&&(identical(other.document, _this.document) || other.document == _this.document)&&const DeepCollectionEquality().equals(other.issues, _this.issues));
}


@override
int get hashCode {
  final _this = this as ModeValidationResult;
  return Object.hash(runtimeType,_this.document,const DeepCollectionEquality().hash(_this.issues));
}



}

/// @nodoc
abstract mixin class $ModeValidationResultCopyWith<$Res>  {
  factory $ModeValidationResultCopyWith(ModeValidationResult value, $Res Function(ModeValidationResult) _then) = _$ModeValidationResultCopyWithImpl;
@useResult
$Res call({
 ModeDocument? document, List<ValidationIssue> issues
});


$ModeDocumentCopyWith<$Res>? get document;

}
/// @nodoc
class _$ModeValidationResultCopyWithImpl<$Res>
    implements $ModeValidationResultCopyWith<$Res> {
  _$ModeValidationResultCopyWithImpl(this._self, this._then);

  final ModeValidationResult _self;
  final $Res Function(ModeValidationResult) _then;

/// Create a copy of ModeValidationResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? document = freezed,Object? issues = null,}) {
  return _then(ModeValidationResult(
document: freezed == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as ModeDocument?,issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as List<ValidationIssue>,
  ));
}
/// Create a copy of ModeValidationResult
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
}
}


/// Adds pattern-matching-related methods to [ModeValidationResult].
extension ModeValidationResultPatterns on ModeValidationResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeValidationResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeValidationResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeValidationResult value)  $default,){
final _that = this;
switch (_that) {
case _ModeValidationResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeValidationResult value)?  $default,){
final _that = this;
switch (_that) {
case _ModeValidationResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModeDocument? document,  List<ValidationIssue> issues)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeValidationResult() when $default != null:
return $default(_that.document,_that.issues);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModeDocument? document,  List<ValidationIssue> issues)  $default,) {final _that = this;
switch (_that) {
case _ModeValidationResult():
return $default(_that.document,_that.issues);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModeDocument? document,  List<ValidationIssue> issues)?  $default,) {final _that = this;
switch (_that) {
case _ModeValidationResult() when $default != null:
return $default(_that.document,_that.issues);case _:
  return null;

}
}

}

/// @nodoc


class _ModeValidationResult implements ModeValidationResult {
  const _ModeValidationResult({required this.document, required  List<ValidationIssue> issues}): _issues = issues;


@override final  ModeDocument? document;
 final  List<ValidationIssue> _issues;
@override List<ValidationIssue> get issues {
  if (_issues is EqualUnmodifiableListView) return _issues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_issues);
}


/// Create a copy of ModeValidationResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeValidationResultCopyWith<_ModeValidationResult> get copyWith => __$ModeValidationResultCopyWithImpl<_ModeValidationResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeValidationResult&&(identical(other.document, document) || other.document == document)&&const DeepCollectionEquality().equals(other.issues, _issues));
}


@override
int get hashCode {
    return Object.hash(runtimeType,document,const DeepCollectionEquality().hash(_issues));
}



}

/// @nodoc
abstract mixin class _$ModeValidationResultCopyWith<$Res> implements $ModeValidationResultCopyWith<$Res> {
  factory _$ModeValidationResultCopyWith(_ModeValidationResult value, $Res Function(_ModeValidationResult) _then) = __$ModeValidationResultCopyWithImpl;
@override @useResult
$Res call({
 ModeDocument? document, List<ValidationIssue> issues
});


@override $ModeDocumentCopyWith<$Res>? get document;

}
/// @nodoc
class __$ModeValidationResultCopyWithImpl<$Res>
    implements _$ModeValidationResultCopyWith<$Res> {
  __$ModeValidationResultCopyWithImpl(this._self, this._then);

  final _ModeValidationResult _self;
  final $Res Function(_ModeValidationResult) _then;

/// Create a copy of ModeValidationResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? document = freezed,Object? issues = null,}) {
  return _then(_ModeValidationResult(
document: freezed == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as ModeDocument?,issues: null == issues ? _self._issues : issues // ignore: cast_nullable_to_non_nullable
as List<ValidationIssue>,
  ));
}

/// Create a copy of ModeValidationResult
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
}
}

/// @nodoc
mixin _$WorkflowPreviewRequest {

 ModeDocument get document; List<String> get path; String? get targetStateId; String get reason;
/// Create a copy of WorkflowPreviewRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowPreviewRequestCopyWith<WorkflowPreviewRequest> get copyWith => _$WorkflowPreviewRequestCopyWithImpl<WorkflowPreviewRequest>(this as WorkflowPreviewRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkflowPreviewRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowPreviewRequest&&(identical(other.document, _this.document) || other.document == _this.document)&&const DeepCollectionEquality().equals(other.path, _this.path)&&(identical(other.targetStateId, _this.targetStateId) || other.targetStateId == _this.targetStateId)&&(identical(other.reason, _this.reason) || other.reason == _this.reason));
}


@override
int get hashCode {
  final _this = this as WorkflowPreviewRequest;
  return Object.hash(runtimeType,_this.document,const DeepCollectionEquality().hash(_this.path),_this.targetStateId,_this.reason);
}



}

/// @nodoc
abstract mixin class $WorkflowPreviewRequestCopyWith<$Res>  {
  factory $WorkflowPreviewRequestCopyWith(WorkflowPreviewRequest value, $Res Function(WorkflowPreviewRequest) _then) = _$WorkflowPreviewRequestCopyWithImpl;
@useResult
$Res call({
 ModeDocument document, List<String> path, String? targetStateId, String reason
});


$ModeDocumentCopyWith<$Res> get document;

}
/// @nodoc
class _$WorkflowPreviewRequestCopyWithImpl<$Res>
    implements $WorkflowPreviewRequestCopyWith<$Res> {
  _$WorkflowPreviewRequestCopyWithImpl(this._self, this._then);

  final WorkflowPreviewRequest _self;
  final $Res Function(WorkflowPreviewRequest) _then;

/// Create a copy of WorkflowPreviewRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? document = null,Object? path = null,Object? targetStateId = freezed,Object? reason = null,}) {
  return _then(WorkflowPreviewRequest(
document: null == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as ModeDocument,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as List<String>,targetStateId: freezed == targetStateId ? _self.targetStateId : targetStateId // ignore: cast_nullable_to_non_nullable
as String?,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of WorkflowPreviewRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDocumentCopyWith<$Res> get document {

  return $ModeDocumentCopyWith<$Res>(_self.document, (value) {
    return _then(_self.copyWith(document: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkflowPreviewRequest].
extension WorkflowPreviewRequestPatterns on WorkflowPreviewRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowPreviewRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowPreviewRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowPreviewRequest value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowPreviewRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowPreviewRequest value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowPreviewRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModeDocument document,  List<String> path,  String? targetStateId,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowPreviewRequest() when $default != null:
return $default(_that.document,_that.path,_that.targetStateId,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModeDocument document,  List<String> path,  String? targetStateId,  String reason)  $default,) {final _that = this;
switch (_that) {
case _WorkflowPreviewRequest():
return $default(_that.document,_that.path,_that.targetStateId,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModeDocument document,  List<String> path,  String? targetStateId,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowPreviewRequest() when $default != null:
return $default(_that.document,_that.path,_that.targetStateId,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowPreviewRequest implements WorkflowPreviewRequest {
  const _WorkflowPreviewRequest({required this.document, required  List<String> path, required this.targetStateId, required this.reason}): _path = path;


@override final  ModeDocument document;
 final  List<String> _path;
@override List<String> get path {
  if (_path is EqualUnmodifiableListView) return _path;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_path);
}

@override final  String? targetStateId;
@override final  String reason;

/// Create a copy of WorkflowPreviewRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowPreviewRequestCopyWith<_WorkflowPreviewRequest> get copyWith => __$WorkflowPreviewRequestCopyWithImpl<_WorkflowPreviewRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowPreviewRequest&&(identical(other.document, document) || other.document == document)&&const DeepCollectionEquality().equals(other.path, _path)&&(identical(other.targetStateId, targetStateId) || other.targetStateId == targetStateId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,document,const DeepCollectionEquality().hash(_path),targetStateId,reason);
}



}

/// @nodoc
abstract mixin class _$WorkflowPreviewRequestCopyWith<$Res> implements $WorkflowPreviewRequestCopyWith<$Res> {
  factory _$WorkflowPreviewRequestCopyWith(_WorkflowPreviewRequest value, $Res Function(_WorkflowPreviewRequest) _then) = __$WorkflowPreviewRequestCopyWithImpl;
@override @useResult
$Res call({
 ModeDocument document, List<String> path, String? targetStateId, String reason
});


@override $ModeDocumentCopyWith<$Res> get document;

}
/// @nodoc
class __$WorkflowPreviewRequestCopyWithImpl<$Res>
    implements _$WorkflowPreviewRequestCopyWith<$Res> {
  __$WorkflowPreviewRequestCopyWithImpl(this._self, this._then);

  final _WorkflowPreviewRequest _self;
  final $Res Function(_WorkflowPreviewRequest) _then;

/// Create a copy of WorkflowPreviewRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? document = null,Object? path = null,Object? targetStateId = freezed,Object? reason = null,}) {
  return _then(_WorkflowPreviewRequest(
document: null == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as ModeDocument,path: null == path ? _self._path : path // ignore: cast_nullable_to_non_nullable
as List<String>,targetStateId: freezed == targetStateId ? _self.targetStateId : targetStateId // ignore: cast_nullable_to_non_nullable
as String?,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of WorkflowPreviewRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDocumentCopyWith<$Res> get document {

  return $ModeDocumentCopyWith<$Res>(_self.document, (value) {
    return _then(_self.copyWith(document: value));
  });
}
}

/// @nodoc
mixin _$WorkflowPreviewSnapshot {

 bool get accepted; String get message; WorkflowState? get currentState; List<WorkflowTransition> get transitions; List<String> get path; bool get terminal;
/// Create a copy of WorkflowPreviewSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowPreviewSnapshotCopyWith<WorkflowPreviewSnapshot> get copyWith => _$WorkflowPreviewSnapshotCopyWithImpl<WorkflowPreviewSnapshot>(this as WorkflowPreviewSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkflowPreviewSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowPreviewSnapshot&&(identical(other.accepted, _this.accepted) || other.accepted == _this.accepted)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.currentState, _this.currentState) || other.currentState == _this.currentState)&&const DeepCollectionEquality().equals(other.transitions, _this.transitions)&&const DeepCollectionEquality().equals(other.path, _this.path)&&(identical(other.terminal, _this.terminal) || other.terminal == _this.terminal));
}


@override
int get hashCode {
  final _this = this as WorkflowPreviewSnapshot;
  return Object.hash(runtimeType,_this.accepted,_this.message,_this.currentState,const DeepCollectionEquality().hash(_this.transitions),const DeepCollectionEquality().hash(_this.path),_this.terminal);
}



}

/// @nodoc
abstract mixin class $WorkflowPreviewSnapshotCopyWith<$Res>  {
  factory $WorkflowPreviewSnapshotCopyWith(WorkflowPreviewSnapshot value, $Res Function(WorkflowPreviewSnapshot) _then) = _$WorkflowPreviewSnapshotCopyWithImpl;
@useResult
$Res call({
 bool accepted, String message, WorkflowState? currentState, List<WorkflowTransition> transitions, List<String> path, bool terminal
});


$WorkflowStateCopyWith<$Res>? get currentState;

}
/// @nodoc
class _$WorkflowPreviewSnapshotCopyWithImpl<$Res>
    implements $WorkflowPreviewSnapshotCopyWith<$Res> {
  _$WorkflowPreviewSnapshotCopyWithImpl(this._self, this._then);

  final WorkflowPreviewSnapshot _self;
  final $Res Function(WorkflowPreviewSnapshot) _then;

/// Create a copy of WorkflowPreviewSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accepted = null,Object? message = null,Object? currentState = freezed,Object? transitions = null,Object? path = null,Object? terminal = null,}) {
  return _then(WorkflowPreviewSnapshot(
accepted: null == accepted ? _self.accepted : accepted // ignore: cast_nullable_to_non_nullable
as bool,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,currentState: freezed == currentState ? _self.currentState : currentState // ignore: cast_nullable_to_non_nullable
as WorkflowState?,transitions: null == transitions ? _self.transitions : transitions // ignore: cast_nullable_to_non_nullable
as List<WorkflowTransition>,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as List<String>,terminal: null == terminal ? _self.terminal : terminal // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of WorkflowPreviewSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowStateCopyWith<$Res>? get currentState {
    if (_self.currentState == null) {
    return null;
  }

  return $WorkflowStateCopyWith<$Res>(_self.currentState!, (value) {
    return _then(_self.copyWith(currentState: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkflowPreviewSnapshot].
extension WorkflowPreviewSnapshotPatterns on WorkflowPreviewSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowPreviewSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowPreviewSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowPreviewSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowPreviewSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowPreviewSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowPreviewSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool accepted,  String message,  WorkflowState? currentState,  List<WorkflowTransition> transitions,  List<String> path,  bool terminal)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowPreviewSnapshot() when $default != null:
return $default(_that.accepted,_that.message,_that.currentState,_that.transitions,_that.path,_that.terminal);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool accepted,  String message,  WorkflowState? currentState,  List<WorkflowTransition> transitions,  List<String> path,  bool terminal)  $default,) {final _that = this;
switch (_that) {
case _WorkflowPreviewSnapshot():
return $default(_that.accepted,_that.message,_that.currentState,_that.transitions,_that.path,_that.terminal);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool accepted,  String message,  WorkflowState? currentState,  List<WorkflowTransition> transitions,  List<String> path,  bool terminal)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowPreviewSnapshot() when $default != null:
return $default(_that.accepted,_that.message,_that.currentState,_that.transitions,_that.path,_that.terminal);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowPreviewSnapshot implements WorkflowPreviewSnapshot {
  const _WorkflowPreviewSnapshot({required this.accepted, required this.message, required this.currentState, required  List<WorkflowTransition> transitions, required  List<String> path, required this.terminal}): _transitions = transitions,_path = path;


@override final  bool accepted;
@override final  String message;
@override final  WorkflowState? currentState;
 final  List<WorkflowTransition> _transitions;
@override List<WorkflowTransition> get transitions {
  if (_transitions is EqualUnmodifiableListView) return _transitions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_transitions);
}

 final  List<String> _path;
@override List<String> get path {
  if (_path is EqualUnmodifiableListView) return _path;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_path);
}

@override final  bool terminal;

/// Create a copy of WorkflowPreviewSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowPreviewSnapshotCopyWith<_WorkflowPreviewSnapshot> get copyWith => __$WorkflowPreviewSnapshotCopyWithImpl<_WorkflowPreviewSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowPreviewSnapshot&&(identical(other.accepted, accepted) || other.accepted == accepted)&&(identical(other.message, message) || other.message == message)&&(identical(other.currentState, currentState) || other.currentState == currentState)&&const DeepCollectionEquality().equals(other.transitions, _transitions)&&const DeepCollectionEquality().equals(other.path, _path)&&(identical(other.terminal, terminal) || other.terminal == terminal));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accepted,message,currentState,const DeepCollectionEquality().hash(_transitions),const DeepCollectionEquality().hash(_path),terminal);
}



}

/// @nodoc
abstract mixin class _$WorkflowPreviewSnapshotCopyWith<$Res> implements $WorkflowPreviewSnapshotCopyWith<$Res> {
  factory _$WorkflowPreviewSnapshotCopyWith(_WorkflowPreviewSnapshot value, $Res Function(_WorkflowPreviewSnapshot) _then) = __$WorkflowPreviewSnapshotCopyWithImpl;
@override @useResult
$Res call({
 bool accepted, String message, WorkflowState? currentState, List<WorkflowTransition> transitions, List<String> path, bool terminal
});


@override $WorkflowStateCopyWith<$Res>? get currentState;

}
/// @nodoc
class __$WorkflowPreviewSnapshotCopyWithImpl<$Res>
    implements _$WorkflowPreviewSnapshotCopyWith<$Res> {
  __$WorkflowPreviewSnapshotCopyWithImpl(this._self, this._then);

  final _WorkflowPreviewSnapshot _self;
  final $Res Function(_WorkflowPreviewSnapshot) _then;

/// Create a copy of WorkflowPreviewSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accepted = null,Object? message = null,Object? currentState = freezed,Object? transitions = null,Object? path = null,Object? terminal = null,}) {
  return _then(_WorkflowPreviewSnapshot(
accepted: null == accepted ? _self.accepted : accepted // ignore: cast_nullable_to_non_nullable
as bool,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,currentState: freezed == currentState ? _self.currentState : currentState // ignore: cast_nullable_to_non_nullable
as WorkflowState?,transitions: null == transitions ? _self._transitions : transitions // ignore: cast_nullable_to_non_nullable
as List<WorkflowTransition>,path: null == path ? _self._path : path // ignore: cast_nullable_to_non_nullable
as List<String>,terminal: null == terminal ? _self.terminal : terminal // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of WorkflowPreviewSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowStateCopyWith<$Res>? get currentState {
    if (_self.currentState == null) {
    return null;
  }

  return $WorkflowStateCopyWith<$Res>(_self.currentState!, (value) {
    return _then(_self.copyWith(currentState: value));
  });
}
}

// dart format on
