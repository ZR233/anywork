// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountEditorKey {

 String get editorId; AccountDisplayKey get target; bool get creating; AccountTemplateKey? get template;
/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountEditorKeyCopyWith<AccountEditorKey> get copyWith => _$AccountEditorKeyCopyWithImpl<AccountEditorKey>(this as AccountEditorKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountEditorKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountEditorKey&&(identical(other.editorId, _this.editorId) || other.editorId == _this.editorId)&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.creating, _this.creating) || other.creating == _this.creating)&&(identical(other.template, _this.template) || other.template == _this.template));
}


@override
int get hashCode {
  final _this = this as AccountEditorKey;
  return Object.hash(runtimeType,_this.editorId,_this.target,_this.creating,_this.template);
}

@override
String toString() {
  final _this = this as AccountEditorKey;
  return 'AccountEditorKey(editorId: ${_this.editorId}, target: ${_this.target}, creating: ${_this.creating}, template: ${_this.template})';
}


}

/// @nodoc
abstract mixin class $AccountEditorKeyCopyWith<$Res>  {
  factory $AccountEditorKeyCopyWith(AccountEditorKey value, $Res Function(AccountEditorKey) _then) = _$AccountEditorKeyCopyWithImpl;
@useResult
$Res call({
 String editorId, AccountDisplayKey target, bool creating, AccountTemplateKey? template
});


$AccountDisplayKeyCopyWith<$Res> get target;$AccountTemplateKeyCopyWith<$Res>? get template;

}
/// @nodoc
class _$AccountEditorKeyCopyWithImpl<$Res>
    implements $AccountEditorKeyCopyWith<$Res> {
  _$AccountEditorKeyCopyWithImpl(this._self, this._then);

  final AccountEditorKey _self;
  final $Res Function(AccountEditorKey) _then;

/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? editorId = null,Object? target = null,Object? creating = null,Object? template = freezed,}) {
  return _then(AccountEditorKey(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as String,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey,creating: null == creating ? _self.creating : creating // ignore: cast_nullable_to_non_nullable
as bool,template: freezed == template ? _self.template : template // ignore: cast_nullable_to_non_nullable
as AccountTemplateKey?,
  ));
}
/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res> get target {

  return $AccountDisplayKeyCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplateKeyCopyWith<$Res>? get template {
    if (_self.template == null) {
    return null;
  }

  return $AccountTemplateKeyCopyWith<$Res>(_self.template!, (value) {
    return _then(_self.copyWith(template: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountEditorKey].
extension AccountEditorKeyPatterns on AccountEditorKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountEditorKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountEditorKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountEditorKey value)  $default,){
final _that = this;
switch (_that) {
case _AccountEditorKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountEditorKey value)?  $default,){
final _that = this;
switch (_that) {
case _AccountEditorKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String editorId,  AccountDisplayKey target,  bool creating,  AccountTemplateKey? template)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountEditorKey() when $default != null:
return $default(_that.editorId,_that.target,_that.creating,_that.template);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String editorId,  AccountDisplayKey target,  bool creating,  AccountTemplateKey? template)  $default,) {final _that = this;
switch (_that) {
case _AccountEditorKey():
return $default(_that.editorId,_that.target,_that.creating,_that.template);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String editorId,  AccountDisplayKey target,  bool creating,  AccountTemplateKey? template)?  $default,) {final _that = this;
switch (_that) {
case _AccountEditorKey() when $default != null:
return $default(_that.editorId,_that.target,_that.creating,_that.template);case _:
  return null;

}
}

}

/// @nodoc


class _AccountEditorKey implements AccountEditorKey {
  const _AccountEditorKey({required this.editorId, required this.target, required this.creating, this.template});


@override final  String editorId;
@override final  AccountDisplayKey target;
@override final  bool creating;
@override final  AccountTemplateKey? template;

/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountEditorKeyCopyWith<_AccountEditorKey> get copyWith => __$AccountEditorKeyCopyWithImpl<_AccountEditorKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountEditorKey&&(identical(other.editorId, editorId) || other.editorId == editorId)&&(identical(other.target, target) || other.target == target)&&(identical(other.creating, creating) || other.creating == creating)&&(identical(other.template, template) || other.template == template));
}


@override
int get hashCode {
    return Object.hash(runtimeType,editorId,target,creating,template);
}

@override
String toString() {
    return 'AccountEditorKey(editorId: $editorId, target: $target, creating: $creating, template: $template)';
}


}

/// @nodoc
abstract mixin class _$AccountEditorKeyCopyWith<$Res> implements $AccountEditorKeyCopyWith<$Res> {
  factory _$AccountEditorKeyCopyWith(_AccountEditorKey value, $Res Function(_AccountEditorKey) _then) = __$AccountEditorKeyCopyWithImpl;
@override @useResult
$Res call({
 String editorId, AccountDisplayKey target, bool creating, AccountTemplateKey? template
});


@override $AccountDisplayKeyCopyWith<$Res> get target;@override $AccountTemplateKeyCopyWith<$Res>? get template;

}
/// @nodoc
class __$AccountEditorKeyCopyWithImpl<$Res>
    implements _$AccountEditorKeyCopyWith<$Res> {
  __$AccountEditorKeyCopyWithImpl(this._self, this._then);

  final _AccountEditorKey _self;
  final $Res Function(_AccountEditorKey) _then;

/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? editorId = null,Object? target = null,Object? creating = null,Object? template = freezed,}) {
  return _then(_AccountEditorKey(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as String,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey,creating: null == creating ? _self.creating : creating // ignore: cast_nullable_to_non_nullable
as bool,template: freezed == template ? _self.template : template // ignore: cast_nullable_to_non_nullable
as AccountTemplateKey?,
  ));
}

/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res> get target {

  return $AccountDisplayKeyCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplateKeyCopyWith<$Res>? get template {
    if (_self.template == null) {
    return null;
  }

  return $AccountTemplateKeyCopyWith<$Res>(_self.template!, (value) {
    return _then(_self.copyWith(template: value));
  });
}
}

/// @nodoc
mixin _$AccountActionPresentation {

 String get ownerEpoch; int? get acpConnectionRevision; bool get pending; String? get message;
/// Create a copy of AccountActionPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountActionPresentationCopyWith<AccountActionPresentation> get copyWith => _$AccountActionPresentationCopyWithImpl<AccountActionPresentation>(this as AccountActionPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountActionPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountActionPresentation&&(identical(other.ownerEpoch, _this.ownerEpoch) || other.ownerEpoch == _this.ownerEpoch)&&(identical(other.acpConnectionRevision, _this.acpConnectionRevision) || other.acpConnectionRevision == _this.acpConnectionRevision)&&(identical(other.pending, _this.pending) || other.pending == _this.pending)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as AccountActionPresentation;
  return Object.hash(runtimeType,_this.ownerEpoch,_this.acpConnectionRevision,_this.pending,_this.message);
}

@override
String toString() {
  final _this = this as AccountActionPresentation;
  return 'AccountActionPresentation(ownerEpoch: ${_this.ownerEpoch}, acpConnectionRevision: ${_this.acpConnectionRevision}, pending: ${_this.pending}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $AccountActionPresentationCopyWith<$Res>  {
  factory $AccountActionPresentationCopyWith(AccountActionPresentation value, $Res Function(AccountActionPresentation) _then) = _$AccountActionPresentationCopyWithImpl;
@useResult
$Res call({
 String ownerEpoch, int? acpConnectionRevision, bool pending, String? message
});




}
/// @nodoc
class _$AccountActionPresentationCopyWithImpl<$Res>
    implements $AccountActionPresentationCopyWith<$Res> {
  _$AccountActionPresentationCopyWithImpl(this._self, this._then);

  final AccountActionPresentation _self;
  final $Res Function(AccountActionPresentation) _then;

/// Create a copy of AccountActionPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ownerEpoch = null,Object? acpConnectionRevision = freezed,Object? pending = null,Object? message = freezed,}) {
  return _then(AccountActionPresentation(
ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,acpConnectionRevision: freezed == acpConnectionRevision ? _self.acpConnectionRevision : acpConnectionRevision // ignore: cast_nullable_to_non_nullable
as int?,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountActionPresentation].
extension AccountActionPresentationPatterns on AccountActionPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountActionPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountActionPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountActionPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountActionPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountActionPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountActionPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ownerEpoch,  int? acpConnectionRevision,  bool pending,  String? message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountActionPresentation() when $default != null:
return $default(_that.ownerEpoch,_that.acpConnectionRevision,_that.pending,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ownerEpoch,  int? acpConnectionRevision,  bool pending,  String? message)  $default,) {final _that = this;
switch (_that) {
case _AccountActionPresentation():
return $default(_that.ownerEpoch,_that.acpConnectionRevision,_that.pending,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ownerEpoch,  int? acpConnectionRevision,  bool pending,  String? message)?  $default,) {final _that = this;
switch (_that) {
case _AccountActionPresentation() when $default != null:
return $default(_that.ownerEpoch,_that.acpConnectionRevision,_that.pending,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _AccountActionPresentation implements AccountActionPresentation {
  const _AccountActionPresentation({required this.ownerEpoch, this.acpConnectionRevision, this.pending = false, this.message});


@override final  String ownerEpoch;
@override final  int? acpConnectionRevision;
@override@JsonKey() final  bool pending;
@override final  String? message;

/// Create a copy of AccountActionPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountActionPresentationCopyWith<_AccountActionPresentation> get copyWith => __$AccountActionPresentationCopyWithImpl<_AccountActionPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountActionPresentation&&(identical(other.ownerEpoch, ownerEpoch) || other.ownerEpoch == ownerEpoch)&&(identical(other.acpConnectionRevision, acpConnectionRevision) || other.acpConnectionRevision == acpConnectionRevision)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,ownerEpoch,acpConnectionRevision,pending,message);
}

@override
String toString() {
    return 'AccountActionPresentation(ownerEpoch: $ownerEpoch, acpConnectionRevision: $acpConnectionRevision, pending: $pending, message: $message)';
}


}

/// @nodoc
abstract mixin class _$AccountActionPresentationCopyWith<$Res> implements $AccountActionPresentationCopyWith<$Res> {
  factory _$AccountActionPresentationCopyWith(_AccountActionPresentation value, $Res Function(_AccountActionPresentation) _then) = __$AccountActionPresentationCopyWithImpl;
@override @useResult
$Res call({
 String ownerEpoch, int? acpConnectionRevision, bool pending, String? message
});




}
/// @nodoc
class __$AccountActionPresentationCopyWithImpl<$Res>
    implements _$AccountActionPresentationCopyWith<$Res> {
  __$AccountActionPresentationCopyWithImpl(this._self, this._then);

  final _AccountActionPresentation _self;
  final $Res Function(_AccountActionPresentation) _then;

/// Create a copy of AccountActionPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ownerEpoch = null,Object? acpConnectionRevision = freezed,Object? pending = null,Object? message = freezed,}) {
  return _then(_AccountActionPresentation(
ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,acpConnectionRevision: freezed == acpConnectionRevision ? _self.acpConnectionRevision : acpConnectionRevision // ignore: cast_nullable_to_non_nullable
as int?,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AccountsViewState {

 AccountsListPresentation get list; AccountDisplayKey? get selected; AccountEditorKey? get editor; bool get choosingTemplate; bool get templatesLoading; List<AccountTemplatePresentation> get templates; String? get templateError; Map<AccountDisplayKey, AccountActionPresentation> get actions;
/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountsViewStateCopyWith<AccountsViewState> get copyWith => _$AccountsViewStateCopyWithImpl<AccountsViewState>(this as AccountsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountsViewState&&(identical(other.list, _this.list) || other.list == _this.list)&&(identical(other.selected, _this.selected) || other.selected == _this.selected)&&(identical(other.editor, _this.editor) || other.editor == _this.editor)&&(identical(other.choosingTemplate, _this.choosingTemplate) || other.choosingTemplate == _this.choosingTemplate)&&(identical(other.templatesLoading, _this.templatesLoading) || other.templatesLoading == _this.templatesLoading)&&const DeepCollectionEquality().equals(other.templates, _this.templates)&&(identical(other.templateError, _this.templateError) || other.templateError == _this.templateError)&&const DeepCollectionEquality().equals(other.actions, _this.actions));
}


@override
int get hashCode {
  final _this = this as AccountsViewState;
  return Object.hash(runtimeType,_this.list,_this.selected,_this.editor,_this.choosingTemplate,_this.templatesLoading,const DeepCollectionEquality().hash(_this.templates),_this.templateError,const DeepCollectionEquality().hash(_this.actions));
}

@override
String toString() {
  final _this = this as AccountsViewState;
  return 'AccountsViewState(list: ${_this.list}, selected: ${_this.selected}, editor: ${_this.editor}, choosingTemplate: ${_this.choosingTemplate}, templatesLoading: ${_this.templatesLoading}, templates: ${_this.templates}, templateError: ${_this.templateError}, actions: ${_this.actions})';
}


}

/// @nodoc
abstract mixin class $AccountsViewStateCopyWith<$Res>  {
  factory $AccountsViewStateCopyWith(AccountsViewState value, $Res Function(AccountsViewState) _then) = _$AccountsViewStateCopyWithImpl;
@useResult
$Res call({
 AccountsListPresentation list, AccountDisplayKey? selected, AccountEditorKey? editor, bool choosingTemplate, bool templatesLoading, List<AccountTemplatePresentation> templates, String? templateError, Map<AccountDisplayKey, AccountActionPresentation> actions
});


$AccountsListPresentationCopyWith<$Res> get list;$AccountDisplayKeyCopyWith<$Res>? get selected;$AccountEditorKeyCopyWith<$Res>? get editor;

}
/// @nodoc
class _$AccountsViewStateCopyWithImpl<$Res>
    implements $AccountsViewStateCopyWith<$Res> {
  _$AccountsViewStateCopyWithImpl(this._self, this._then);

  final AccountsViewState _self;
  final $Res Function(AccountsViewState) _then;

/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? list = null,Object? selected = freezed,Object? editor = freezed,Object? choosingTemplate = null,Object? templatesLoading = null,Object? templates = null,Object? templateError = freezed,Object? actions = null,}) {
  return _then(AccountsViewState(
list: null == list ? _self.list : list // ignore: cast_nullable_to_non_nullable
as AccountsListPresentation,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey?,editor: freezed == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as AccountEditorKey?,choosingTemplate: null == choosingTemplate ? _self.choosingTemplate : choosingTemplate // ignore: cast_nullable_to_non_nullable
as bool,templatesLoading: null == templatesLoading ? _self.templatesLoading : templatesLoading // ignore: cast_nullable_to_non_nullable
as bool,templates: null == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as List<AccountTemplatePresentation>,templateError: freezed == templateError ? _self.templateError : templateError // ignore: cast_nullable_to_non_nullable
as String?,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as Map<AccountDisplayKey, AccountActionPresentation>,
  ));
}
/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountsListPresentationCopyWith<$Res> get list {

  return $AccountsListPresentationCopyWith<$Res>(_self.list, (value) {
    return _then(_self.copyWith(list: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res>? get selected {
    if (_self.selected == null) {
    return null;
  }

  return $AccountDisplayKeyCopyWith<$Res>(_self.selected!, (value) {
    return _then(_self.copyWith(selected: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEditorKeyCopyWith<$Res>? get editor {
    if (_self.editor == null) {
    return null;
  }

  return $AccountEditorKeyCopyWith<$Res>(_self.editor!, (value) {
    return _then(_self.copyWith(editor: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountsViewState].
extension AccountsViewStatePatterns on AccountsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountsViewState value)  $default,){
final _that = this;
switch (_that) {
case _AccountsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AccountsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountsListPresentation list,  AccountDisplayKey? selected,  AccountEditorKey? editor,  bool choosingTemplate,  bool templatesLoading,  List<AccountTemplatePresentation> templates,  String? templateError,  Map<AccountDisplayKey, AccountActionPresentation> actions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountsViewState() when $default != null:
return $default(_that.list,_that.selected,_that.editor,_that.choosingTemplate,_that.templatesLoading,_that.templates,_that.templateError,_that.actions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountsListPresentation list,  AccountDisplayKey? selected,  AccountEditorKey? editor,  bool choosingTemplate,  bool templatesLoading,  List<AccountTemplatePresentation> templates,  String? templateError,  Map<AccountDisplayKey, AccountActionPresentation> actions)  $default,) {final _that = this;
switch (_that) {
case _AccountsViewState():
return $default(_that.list,_that.selected,_that.editor,_that.choosingTemplate,_that.templatesLoading,_that.templates,_that.templateError,_that.actions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountsListPresentation list,  AccountDisplayKey? selected,  AccountEditorKey? editor,  bool choosingTemplate,  bool templatesLoading,  List<AccountTemplatePresentation> templates,  String? templateError,  Map<AccountDisplayKey, AccountActionPresentation> actions)?  $default,) {final _that = this;
switch (_that) {
case _AccountsViewState() when $default != null:
return $default(_that.list,_that.selected,_that.editor,_that.choosingTemplate,_that.templatesLoading,_that.templates,_that.templateError,_that.actions);case _:
  return null;

}
}

}

/// @nodoc


class _AccountsViewState implements AccountsViewState {
  const _AccountsViewState({required this.list, this.selected, this.editor, this.choosingTemplate = false, this.templatesLoading = false,  List<AccountTemplatePresentation> templates = const [], this.templateError,  Map<AccountDisplayKey, AccountActionPresentation> actions = const {}}): _templates = templates,_actions = actions;


@override final  AccountsListPresentation list;
@override final  AccountDisplayKey? selected;
@override final  AccountEditorKey? editor;
@override@JsonKey() final  bool choosingTemplate;
@override@JsonKey() final  bool templatesLoading;
 final  List<AccountTemplatePresentation> _templates;
@override@JsonKey() List<AccountTemplatePresentation> get templates {
  if (_templates is EqualUnmodifiableListView) return _templates;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_templates);
}

@override final  String? templateError;
 final  Map<AccountDisplayKey, AccountActionPresentation> _actions;
@override@JsonKey() Map<AccountDisplayKey, AccountActionPresentation> get actions {
  if (_actions is EqualUnmodifiableMapView) return _actions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_actions);
}


/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountsViewStateCopyWith<_AccountsViewState> get copyWith => __$AccountsViewStateCopyWithImpl<_AccountsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountsViewState&&(identical(other.list, list) || other.list == list)&&(identical(other.selected, selected) || other.selected == selected)&&(identical(other.editor, editor) || other.editor == editor)&&(identical(other.choosingTemplate, choosingTemplate) || other.choosingTemplate == choosingTemplate)&&(identical(other.templatesLoading, templatesLoading) || other.templatesLoading == templatesLoading)&&const DeepCollectionEquality().equals(other.templates, _templates)&&(identical(other.templateError, templateError) || other.templateError == templateError)&&const DeepCollectionEquality().equals(other.actions, _actions));
}


@override
int get hashCode {
    return Object.hash(runtimeType,list,selected,editor,choosingTemplate,templatesLoading,const DeepCollectionEquality().hash(_templates),templateError,const DeepCollectionEquality().hash(_actions));
}

@override
String toString() {
    return 'AccountsViewState(list: $list, selected: $selected, editor: $editor, choosingTemplate: $choosingTemplate, templatesLoading: $templatesLoading, templates: $templates, templateError: $templateError, actions: $actions)';
}


}

/// @nodoc
abstract mixin class _$AccountsViewStateCopyWith<$Res> implements $AccountsViewStateCopyWith<$Res> {
  factory _$AccountsViewStateCopyWith(_AccountsViewState value, $Res Function(_AccountsViewState) _then) = __$AccountsViewStateCopyWithImpl;
@override @useResult
$Res call({
 AccountsListPresentation list, AccountDisplayKey? selected, AccountEditorKey? editor, bool choosingTemplate, bool templatesLoading, List<AccountTemplatePresentation> templates, String? templateError, Map<AccountDisplayKey, AccountActionPresentation> actions
});


@override $AccountsListPresentationCopyWith<$Res> get list;@override $AccountDisplayKeyCopyWith<$Res>? get selected;@override $AccountEditorKeyCopyWith<$Res>? get editor;

}
/// @nodoc
class __$AccountsViewStateCopyWithImpl<$Res>
    implements _$AccountsViewStateCopyWith<$Res> {
  __$AccountsViewStateCopyWithImpl(this._self, this._then);

  final _AccountsViewState _self;
  final $Res Function(_AccountsViewState) _then;

/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? list = null,Object? selected = freezed,Object? editor = freezed,Object? choosingTemplate = null,Object? templatesLoading = null,Object? templates = null,Object? templateError = freezed,Object? actions = null,}) {
  return _then(_AccountsViewState(
list: null == list ? _self.list : list // ignore: cast_nullable_to_non_nullable
as AccountsListPresentation,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey?,editor: freezed == editor ? _self.editor : editor // ignore: cast_nullable_to_non_nullable
as AccountEditorKey?,choosingTemplate: null == choosingTemplate ? _self.choosingTemplate : choosingTemplate // ignore: cast_nullable_to_non_nullable
as bool,templatesLoading: null == templatesLoading ? _self.templatesLoading : templatesLoading // ignore: cast_nullable_to_non_nullable
as bool,templates: null == templates ? _self._templates : templates // ignore: cast_nullable_to_non_nullable
as List<AccountTemplatePresentation>,templateError: freezed == templateError ? _self.templateError : templateError // ignore: cast_nullable_to_non_nullable
as String?,actions: null == actions ? _self._actions : actions // ignore: cast_nullable_to_non_nullable
as Map<AccountDisplayKey, AccountActionPresentation>,
  ));
}

/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountsListPresentationCopyWith<$Res> get list {

  return $AccountsListPresentationCopyWith<$Res>(_self.list, (value) {
    return _then(_self.copyWith(list: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res>? get selected {
    if (_self.selected == null) {
    return null;
  }

  return $AccountDisplayKeyCopyWith<$Res>(_self.selected!, (value) {
    return _then(_self.copyWith(selected: value));
  });
}/// Create a copy of AccountsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEditorKeyCopyWith<$Res>? get editor {
    if (_self.editor == null) {
    return null;
  }

  return $AccountEditorKeyCopyWith<$Res>(_self.editor!, (value) {
    return _then(_self.copyWith(editor: value));
  });
}
}

/// @nodoc
mixin _$AccountDetailsViewState {

 AccountDetailsPresentation get details; AccountAcpKey? get acpKey; bool get observed; bool get stale;
/// Create a copy of AccountDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountDetailsViewStateCopyWith<AccountDetailsViewState> get copyWith => _$AccountDetailsViewStateCopyWithImpl<AccountDetailsViewState>(this as AccountDetailsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountDetailsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountDetailsViewState&&(identical(other.details, _this.details) || other.details == _this.details)&&(identical(other.acpKey, _this.acpKey) || other.acpKey == _this.acpKey)&&(identical(other.observed, _this.observed) || other.observed == _this.observed)&&(identical(other.stale, _this.stale) || other.stale == _this.stale));
}


@override
int get hashCode {
  final _this = this as AccountDetailsViewState;
  return Object.hash(runtimeType,_this.details,_this.acpKey,_this.observed,_this.stale);
}

@override
String toString() {
  final _this = this as AccountDetailsViewState;
  return 'AccountDetailsViewState(details: ${_this.details}, acpKey: ${_this.acpKey}, observed: ${_this.observed}, stale: ${_this.stale})';
}


}

/// @nodoc
abstract mixin class $AccountDetailsViewStateCopyWith<$Res>  {
  factory $AccountDetailsViewStateCopyWith(AccountDetailsViewState value, $Res Function(AccountDetailsViewState) _then) = _$AccountDetailsViewStateCopyWithImpl;
@useResult
$Res call({
 AccountDetailsPresentation details, AccountAcpKey? acpKey, bool observed, bool stale
});


$AccountDetailsPresentationCopyWith<$Res> get details;$AccountAcpKeyCopyWith<$Res>? get acpKey;

}
/// @nodoc
class _$AccountDetailsViewStateCopyWithImpl<$Res>
    implements $AccountDetailsViewStateCopyWith<$Res> {
  _$AccountDetailsViewStateCopyWithImpl(this._self, this._then);

  final AccountDetailsViewState _self;
  final $Res Function(AccountDetailsViewState) _then;

/// Create a copy of AccountDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? details = null,Object? acpKey = freezed,Object? observed = null,Object? stale = null,}) {
  return _then(AccountDetailsViewState(
details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as AccountDetailsPresentation,acpKey: freezed == acpKey ? _self.acpKey : acpKey // ignore: cast_nullable_to_non_nullable
as AccountAcpKey?,observed: null == observed ? _self.observed : observed // ignore: cast_nullable_to_non_nullable
as bool,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of AccountDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDetailsPresentationCopyWith<$Res> get details {

  return $AccountDetailsPresentationCopyWith<$Res>(_self.details, (value) {
    return _then(_self.copyWith(details: value));
  });
}/// Create a copy of AccountDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountAcpKeyCopyWith<$Res>? get acpKey {
    if (_self.acpKey == null) {
    return null;
  }

  return $AccountAcpKeyCopyWith<$Res>(_self.acpKey!, (value) {
    return _then(_self.copyWith(acpKey: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountDetailsViewState].
extension AccountDetailsViewStatePatterns on AccountDetailsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountDetailsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountDetailsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountDetailsViewState value)  $default,){
final _that = this;
switch (_that) {
case _AccountDetailsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountDetailsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AccountDetailsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountDetailsPresentation details,  AccountAcpKey? acpKey,  bool observed,  bool stale)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountDetailsViewState() when $default != null:
return $default(_that.details,_that.acpKey,_that.observed,_that.stale);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountDetailsPresentation details,  AccountAcpKey? acpKey,  bool observed,  bool stale)  $default,) {final _that = this;
switch (_that) {
case _AccountDetailsViewState():
return $default(_that.details,_that.acpKey,_that.observed,_that.stale);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountDetailsPresentation details,  AccountAcpKey? acpKey,  bool observed,  bool stale)?  $default,) {final _that = this;
switch (_that) {
case _AccountDetailsViewState() when $default != null:
return $default(_that.details,_that.acpKey,_that.observed,_that.stale);case _:
  return null;

}
}

}

/// @nodoc


class _AccountDetailsViewState implements AccountDetailsViewState {
  const _AccountDetailsViewState({required this.details, this.acpKey, this.observed = false, this.stale = false});


@override final  AccountDetailsPresentation details;
@override final  AccountAcpKey? acpKey;
@override@JsonKey() final  bool observed;
@override@JsonKey() final  bool stale;

/// Create a copy of AccountDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountDetailsViewStateCopyWith<_AccountDetailsViewState> get copyWith => __$AccountDetailsViewStateCopyWithImpl<_AccountDetailsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountDetailsViewState&&(identical(other.details, details) || other.details == details)&&(identical(other.acpKey, acpKey) || other.acpKey == acpKey)&&(identical(other.observed, observed) || other.observed == observed)&&(identical(other.stale, stale) || other.stale == stale));
}


@override
int get hashCode {
    return Object.hash(runtimeType,details,acpKey,observed,stale);
}

@override
String toString() {
    return 'AccountDetailsViewState(details: $details, acpKey: $acpKey, observed: $observed, stale: $stale)';
}


}

/// @nodoc
abstract mixin class _$AccountDetailsViewStateCopyWith<$Res> implements $AccountDetailsViewStateCopyWith<$Res> {
  factory _$AccountDetailsViewStateCopyWith(_AccountDetailsViewState value, $Res Function(_AccountDetailsViewState) _then) = __$AccountDetailsViewStateCopyWithImpl;
@override @useResult
$Res call({
 AccountDetailsPresentation details, AccountAcpKey? acpKey, bool observed, bool stale
});


@override $AccountDetailsPresentationCopyWith<$Res> get details;@override $AccountAcpKeyCopyWith<$Res>? get acpKey;

}
/// @nodoc
class __$AccountDetailsViewStateCopyWithImpl<$Res>
    implements _$AccountDetailsViewStateCopyWith<$Res> {
  __$AccountDetailsViewStateCopyWithImpl(this._self, this._then);

  final _AccountDetailsViewState _self;
  final $Res Function(_AccountDetailsViewState) _then;

/// Create a copy of AccountDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? details = null,Object? acpKey = freezed,Object? observed = null,Object? stale = null,}) {
  return _then(_AccountDetailsViewState(
details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as AccountDetailsPresentation,acpKey: freezed == acpKey ? _self.acpKey : acpKey // ignore: cast_nullable_to_non_nullable
as AccountAcpKey?,observed: null == observed ? _self.observed : observed // ignore: cast_nullable_to_non_nullable
as bool,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of AccountDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDetailsPresentationCopyWith<$Res> get details {

  return $AccountDetailsPresentationCopyWith<$Res>(_self.details, (value) {
    return _then(_self.copyWith(details: value));
  });
}/// Create a copy of AccountDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountAcpKeyCopyWith<$Res>? get acpKey {
    if (_self.acpKey == null) {
    return null;
  }

  return $AccountAcpKeyCopyWith<$Res>(_self.acpKey!, (value) {
    return _then(_self.copyWith(acpKey: value));
  });
}
}

/// @nodoc
mixin _$AccountAcpKey {

 AccountDisplayKey get target; String get providerId; int get connectionRevision; String? get editorId; bool get creating;
/// Create a copy of AccountAcpKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountAcpKeyCopyWith<AccountAcpKey> get copyWith => _$AccountAcpKeyCopyWithImpl<AccountAcpKey>(this as AccountAcpKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountAcpKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountAcpKey&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.providerId, _this.providerId) || other.providerId == _this.providerId)&&(identical(other.connectionRevision, _this.connectionRevision) || other.connectionRevision == _this.connectionRevision)&&(identical(other.editorId, _this.editorId) || other.editorId == _this.editorId)&&(identical(other.creating, _this.creating) || other.creating == _this.creating));
}


@override
int get hashCode {
  final _this = this as AccountAcpKey;
  return Object.hash(runtimeType,_this.target,_this.providerId,_this.connectionRevision,_this.editorId,_this.creating);
}

@override
String toString() {
  final _this = this as AccountAcpKey;
  return 'AccountAcpKey(target: ${_this.target}, providerId: ${_this.providerId}, connectionRevision: ${_this.connectionRevision}, editorId: ${_this.editorId}, creating: ${_this.creating})';
}


}

/// @nodoc
abstract mixin class $AccountAcpKeyCopyWith<$Res>  {
  factory $AccountAcpKeyCopyWith(AccountAcpKey value, $Res Function(AccountAcpKey) _then) = _$AccountAcpKeyCopyWithImpl;
@useResult
$Res call({
 AccountDisplayKey target, String providerId, int connectionRevision, String? editorId, bool creating
});


$AccountDisplayKeyCopyWith<$Res> get target;

}
/// @nodoc
class _$AccountAcpKeyCopyWithImpl<$Res>
    implements $AccountAcpKeyCopyWith<$Res> {
  _$AccountAcpKeyCopyWithImpl(this._self, this._then);

  final AccountAcpKey _self;
  final $Res Function(AccountAcpKey) _then;

/// Create a copy of AccountAcpKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? target = null,Object? providerId = null,Object? connectionRevision = null,Object? editorId = freezed,Object? creating = null,}) {
  return _then(AccountAcpKey(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey,providerId: null == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as String,connectionRevision: null == connectionRevision ? _self.connectionRevision : connectionRevision // ignore: cast_nullable_to_non_nullable
as int,editorId: freezed == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as String?,creating: null == creating ? _self.creating : creating // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of AccountAcpKey
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res> get target {

  return $AccountDisplayKeyCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountAcpKey].
extension AccountAcpKeyPatterns on AccountAcpKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountAcpKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountAcpKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountAcpKey value)  $default,){
final _that = this;
switch (_that) {
case _AccountAcpKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountAcpKey value)?  $default,){
final _that = this;
switch (_that) {
case _AccountAcpKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountDisplayKey target,  String providerId,  int connectionRevision,  String? editorId,  bool creating)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountAcpKey() when $default != null:
return $default(_that.target,_that.providerId,_that.connectionRevision,_that.editorId,_that.creating);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountDisplayKey target,  String providerId,  int connectionRevision,  String? editorId,  bool creating)  $default,) {final _that = this;
switch (_that) {
case _AccountAcpKey():
return $default(_that.target,_that.providerId,_that.connectionRevision,_that.editorId,_that.creating);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountDisplayKey target,  String providerId,  int connectionRevision,  String? editorId,  bool creating)?  $default,) {final _that = this;
switch (_that) {
case _AccountAcpKey() when $default != null:
return $default(_that.target,_that.providerId,_that.connectionRevision,_that.editorId,_that.creating);case _:
  return null;

}
}

}

/// @nodoc


class _AccountAcpKey implements AccountAcpKey {
  const _AccountAcpKey({required this.target, required this.providerId, required this.connectionRevision, this.editorId, this.creating = false});


@override final  AccountDisplayKey target;
@override final  String providerId;
@override final  int connectionRevision;
@override final  String? editorId;
@override@JsonKey() final  bool creating;

/// Create a copy of AccountAcpKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountAcpKeyCopyWith<_AccountAcpKey> get copyWith => __$AccountAcpKeyCopyWithImpl<_AccountAcpKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountAcpKey&&(identical(other.target, target) || other.target == target)&&(identical(other.providerId, providerId) || other.providerId == providerId)&&(identical(other.connectionRevision, connectionRevision) || other.connectionRevision == connectionRevision)&&(identical(other.editorId, editorId) || other.editorId == editorId)&&(identical(other.creating, creating) || other.creating == creating));
}


@override
int get hashCode {
    return Object.hash(runtimeType,target,providerId,connectionRevision,editorId,creating);
}

@override
String toString() {
    return 'AccountAcpKey(target: $target, providerId: $providerId, connectionRevision: $connectionRevision, editorId: $editorId, creating: $creating)';
}


}

/// @nodoc
abstract mixin class _$AccountAcpKeyCopyWith<$Res> implements $AccountAcpKeyCopyWith<$Res> {
  factory _$AccountAcpKeyCopyWith(_AccountAcpKey value, $Res Function(_AccountAcpKey) _then) = __$AccountAcpKeyCopyWithImpl;
@override @useResult
$Res call({
 AccountDisplayKey target, String providerId, int connectionRevision, String? editorId, bool creating
});


@override $AccountDisplayKeyCopyWith<$Res> get target;

}
/// @nodoc
class __$AccountAcpKeyCopyWithImpl<$Res>
    implements _$AccountAcpKeyCopyWith<$Res> {
  __$AccountAcpKeyCopyWithImpl(this._self, this._then);

  final _AccountAcpKey _self;
  final $Res Function(_AccountAcpKey) _then;

/// Create a copy of AccountAcpKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? target = null,Object? providerId = null,Object? connectionRevision = null,Object? editorId = freezed,Object? creating = null,}) {
  return _then(_AccountAcpKey(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey,providerId: null == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as String,connectionRevision: null == connectionRevision ? _self.connectionRevision : connectionRevision // ignore: cast_nullable_to_non_nullable
as int,editorId: freezed == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as String?,creating: null == creating ? _self.creating : creating // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of AccountAcpKey
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res> get target {

  return $AccountDisplayKeyCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}

/// @nodoc
mixin _$AccountReadoutState {

 AccountReadoutPhase get phase; List<AccountDisplayFact> get performance; List<AccountModelEvaluation> get evaluations; String? get error;
/// Create a copy of AccountReadoutState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountReadoutStateCopyWith<AccountReadoutState> get copyWith => _$AccountReadoutStateCopyWithImpl<AccountReadoutState>(this as AccountReadoutState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountReadoutState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountReadoutState&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&const DeepCollectionEquality().equals(other.performance, _this.performance)&&const DeepCollectionEquality().equals(other.evaluations, _this.evaluations)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as AccountReadoutState;
  return Object.hash(runtimeType,_this.phase,const DeepCollectionEquality().hash(_this.performance),const DeepCollectionEquality().hash(_this.evaluations),_this.error);
}

@override
String toString() {
  final _this = this as AccountReadoutState;
  return 'AccountReadoutState(phase: ${_this.phase}, performance: ${_this.performance}, evaluations: ${_this.evaluations}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $AccountReadoutStateCopyWith<$Res>  {
  factory $AccountReadoutStateCopyWith(AccountReadoutState value, $Res Function(AccountReadoutState) _then) = _$AccountReadoutStateCopyWithImpl;
@useResult
$Res call({
 AccountReadoutPhase phase, List<AccountDisplayFact> performance, List<AccountModelEvaluation> evaluations, String? error
});




}
/// @nodoc
class _$AccountReadoutStateCopyWithImpl<$Res>
    implements $AccountReadoutStateCopyWith<$Res> {
  _$AccountReadoutStateCopyWithImpl(this._self, this._then);

  final AccountReadoutState _self;
  final $Res Function(AccountReadoutState) _then;

/// Create a copy of AccountReadoutState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? performance = null,Object? evaluations = null,Object? error = freezed,}) {
  return _then(AccountReadoutState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AccountReadoutPhase,performance: null == performance ? _self.performance : performance // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,evaluations: null == evaluations ? _self.evaluations : evaluations // ignore: cast_nullable_to_non_nullable
as List<AccountModelEvaluation>,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountReadoutState].
extension AccountReadoutStatePatterns on AccountReadoutState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountReadoutState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountReadoutState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountReadoutState value)  $default,){
final _that = this;
switch (_that) {
case _AccountReadoutState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountReadoutState value)?  $default,){
final _that = this;
switch (_that) {
case _AccountReadoutState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountReadoutPhase phase,  List<AccountDisplayFact> performance,  List<AccountModelEvaluation> evaluations,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountReadoutState() when $default != null:
return $default(_that.phase,_that.performance,_that.evaluations,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountReadoutPhase phase,  List<AccountDisplayFact> performance,  List<AccountModelEvaluation> evaluations,  String? error)  $default,) {final _that = this;
switch (_that) {
case _AccountReadoutState():
return $default(_that.phase,_that.performance,_that.evaluations,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountReadoutPhase phase,  List<AccountDisplayFact> performance,  List<AccountModelEvaluation> evaluations,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _AccountReadoutState() when $default != null:
return $default(_that.phase,_that.performance,_that.evaluations,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _AccountReadoutState implements AccountReadoutState {
  const _AccountReadoutState({required this.phase,  List<AccountDisplayFact> performance = const [],  List<AccountModelEvaluation> evaluations = const [], this.error}): _performance = performance,_evaluations = evaluations;


@override final  AccountReadoutPhase phase;
 final  List<AccountDisplayFact> _performance;
@override@JsonKey() List<AccountDisplayFact> get performance {
  if (_performance is EqualUnmodifiableListView) return _performance;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_performance);
}

 final  List<AccountModelEvaluation> _evaluations;
@override@JsonKey() List<AccountModelEvaluation> get evaluations {
  if (_evaluations is EqualUnmodifiableListView) return _evaluations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_evaluations);
}

@override final  String? error;

/// Create a copy of AccountReadoutState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountReadoutStateCopyWith<_AccountReadoutState> get copyWith => __$AccountReadoutStateCopyWithImpl<_AccountReadoutState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountReadoutState&&(identical(other.phase, phase) || other.phase == phase)&&const DeepCollectionEquality().equals(other.performance, _performance)&&const DeepCollectionEquality().equals(other.evaluations, _evaluations)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,const DeepCollectionEquality().hash(_performance),const DeepCollectionEquality().hash(_evaluations),error);
}

@override
String toString() {
    return 'AccountReadoutState(phase: $phase, performance: $performance, evaluations: $evaluations, error: $error)';
}


}

/// @nodoc
abstract mixin class _$AccountReadoutStateCopyWith<$Res> implements $AccountReadoutStateCopyWith<$Res> {
  factory _$AccountReadoutStateCopyWith(_AccountReadoutState value, $Res Function(_AccountReadoutState) _then) = __$AccountReadoutStateCopyWithImpl;
@override @useResult
$Res call({
 AccountReadoutPhase phase, List<AccountDisplayFact> performance, List<AccountModelEvaluation> evaluations, String? error
});




}
/// @nodoc
class __$AccountReadoutStateCopyWithImpl<$Res>
    implements _$AccountReadoutStateCopyWith<$Res> {
  __$AccountReadoutStateCopyWithImpl(this._self, this._then);

  final _AccountReadoutState _self;
  final $Res Function(_AccountReadoutState) _then;

/// Create a copy of AccountReadoutState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? performance = null,Object? evaluations = null,Object? error = freezed,}) {
  return _then(_AccountReadoutState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AccountReadoutPhase,performance: null == performance ? _self._performance : performance // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,evaluations: null == evaluations ? _self._evaluations : evaluations // ignore: cast_nullable_to_non_nullable
as List<AccountModelEvaluation>,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AccountModelsViewState {

 AccountCatalogPresentation get catalog; Map<String, AccountReadoutState> get readouts; bool get stale;
/// Create a copy of AccountModelsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelsViewStateCopyWith<AccountModelsViewState> get copyWith => _$AccountModelsViewStateCopyWithImpl<AccountModelsViewState>(this as AccountModelsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelsViewState&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog)&&const DeepCollectionEquality().equals(other.readouts, _this.readouts)&&(identical(other.stale, _this.stale) || other.stale == _this.stale));
}


@override
int get hashCode {
  final _this = this as AccountModelsViewState;
  return Object.hash(runtimeType,_this.catalog,const DeepCollectionEquality().hash(_this.readouts),_this.stale);
}

@override
String toString() {
  final _this = this as AccountModelsViewState;
  return 'AccountModelsViewState(catalog: ${_this.catalog}, readouts: ${_this.readouts}, stale: ${_this.stale})';
}


}

/// @nodoc
abstract mixin class $AccountModelsViewStateCopyWith<$Res>  {
  factory $AccountModelsViewStateCopyWith(AccountModelsViewState value, $Res Function(AccountModelsViewState) _then) = _$AccountModelsViewStateCopyWithImpl;
@useResult
$Res call({
 AccountCatalogPresentation catalog, Map<String, AccountReadoutState> readouts, bool stale
});


$AccountCatalogPresentationCopyWith<$Res> get catalog;

}
/// @nodoc
class _$AccountModelsViewStateCopyWithImpl<$Res>
    implements $AccountModelsViewStateCopyWith<$Res> {
  _$AccountModelsViewStateCopyWithImpl(this._self, this._then);

  final AccountModelsViewState _self;
  final $Res Function(AccountModelsViewState) _then;

/// Create a copy of AccountModelsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? catalog = null,Object? readouts = null,Object? stale = null,}) {
  return _then(AccountModelsViewState(
catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as AccountCatalogPresentation,readouts: null == readouts ? _self.readouts : readouts // ignore: cast_nullable_to_non_nullable
as Map<String, AccountReadoutState>,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of AccountModelsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountCatalogPresentationCopyWith<$Res> get catalog {

  return $AccountCatalogPresentationCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountModelsViewState].
extension AccountModelsViewStatePatterns on AccountModelsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelsViewState value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountCatalogPresentation catalog,  Map<String, AccountReadoutState> readouts,  bool stale)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelsViewState() when $default != null:
return $default(_that.catalog,_that.readouts,_that.stale);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountCatalogPresentation catalog,  Map<String, AccountReadoutState> readouts,  bool stale)  $default,) {final _that = this;
switch (_that) {
case _AccountModelsViewState():
return $default(_that.catalog,_that.readouts,_that.stale);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountCatalogPresentation catalog,  Map<String, AccountReadoutState> readouts,  bool stale)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelsViewState() when $default != null:
return $default(_that.catalog,_that.readouts,_that.stale);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelsViewState implements AccountModelsViewState {
  const _AccountModelsViewState({required this.catalog,  Map<String, AccountReadoutState> readouts = const {}, this.stale = false}): _readouts = readouts;


@override final  AccountCatalogPresentation catalog;
 final  Map<String, AccountReadoutState> _readouts;
@override@JsonKey() Map<String, AccountReadoutState> get readouts {
  if (_readouts is EqualUnmodifiableMapView) return _readouts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readouts);
}

@override@JsonKey() final  bool stale;

/// Create a copy of AccountModelsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelsViewStateCopyWith<_AccountModelsViewState> get copyWith => __$AccountModelsViewStateCopyWithImpl<_AccountModelsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelsViewState&&(identical(other.catalog, catalog) || other.catalog == catalog)&&const DeepCollectionEquality().equals(other.readouts, _readouts)&&(identical(other.stale, stale) || other.stale == stale));
}


@override
int get hashCode {
    return Object.hash(runtimeType,catalog,const DeepCollectionEquality().hash(_readouts),stale);
}

@override
String toString() {
    return 'AccountModelsViewState(catalog: $catalog, readouts: $readouts, stale: $stale)';
}


}

/// @nodoc
abstract mixin class _$AccountModelsViewStateCopyWith<$Res> implements $AccountModelsViewStateCopyWith<$Res> {
  factory _$AccountModelsViewStateCopyWith(_AccountModelsViewState value, $Res Function(_AccountModelsViewState) _then) = __$AccountModelsViewStateCopyWithImpl;
@override @useResult
$Res call({
 AccountCatalogPresentation catalog, Map<String, AccountReadoutState> readouts, bool stale
});


@override $AccountCatalogPresentationCopyWith<$Res> get catalog;

}
/// @nodoc
class __$AccountModelsViewStateCopyWithImpl<$Res>
    implements _$AccountModelsViewStateCopyWith<$Res> {
  __$AccountModelsViewStateCopyWithImpl(this._self, this._then);

  final _AccountModelsViewState _self;
  final $Res Function(_AccountModelsViewState) _then;

/// Create a copy of AccountModelsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? catalog = null,Object? readouts = null,Object? stale = null,}) {
  return _then(_AccountModelsViewState(
catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as AccountCatalogPresentation,readouts: null == readouts ? _self._readouts : readouts // ignore: cast_nullable_to_non_nullable
as Map<String, AccountReadoutState>,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of AccountModelsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountCatalogPresentationCopyWith<$Res> get catalog {

  return $AccountCatalogPresentationCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}
}

/// @nodoc
mixin _$AccountEditorViewState {

 AccountEditorKey get key; NativeAccountEditorPresentation? get native; AcpAccountEditorPresentation? get acp; AccountAcpKey? get acpKey; bool get loading; bool get dirty; bool get saving; bool get canSave; int get draftRevision; bool get stale; String? get error;
/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountEditorViewStateCopyWith<AccountEditorViewState> get copyWith => _$AccountEditorViewStateCopyWithImpl<AccountEditorViewState>(this as AccountEditorViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountEditorViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountEditorViewState&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.native, _this.native) || other.native == _this.native)&&(identical(other.acp, _this.acp) || other.acp == _this.acp)&&(identical(other.acpKey, _this.acpKey) || other.acpKey == _this.acpKey)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&(identical(other.saving, _this.saving) || other.saving == _this.saving)&&(identical(other.canSave, _this.canSave) || other.canSave == _this.canSave)&&(identical(other.draftRevision, _this.draftRevision) || other.draftRevision == _this.draftRevision)&&(identical(other.stale, _this.stale) || other.stale == _this.stale)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as AccountEditorViewState;
  return Object.hash(runtimeType,_this.key,_this.native,_this.acp,_this.acpKey,_this.loading,_this.dirty,_this.saving,_this.canSave,_this.draftRevision,_this.stale,_this.error);
}

@override
String toString() {
  final _this = this as AccountEditorViewState;
  return 'AccountEditorViewState(key: ${_this.key}, native: ${_this.native}, acp: ${_this.acp}, acpKey: ${_this.acpKey}, loading: ${_this.loading}, dirty: ${_this.dirty}, saving: ${_this.saving}, canSave: ${_this.canSave}, draftRevision: ${_this.draftRevision}, stale: ${_this.stale}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $AccountEditorViewStateCopyWith<$Res>  {
  factory $AccountEditorViewStateCopyWith(AccountEditorViewState value, $Res Function(AccountEditorViewState) _then) = _$AccountEditorViewStateCopyWithImpl;
@useResult
$Res call({
 AccountEditorKey key, NativeAccountEditorPresentation? native, AcpAccountEditorPresentation? acp, AccountAcpKey? acpKey, bool loading, bool dirty, bool saving, bool canSave, int draftRevision, bool stale, String? error
});


$AccountEditorKeyCopyWith<$Res> get key;$NativeAccountEditorPresentationCopyWith<$Res>? get native;$AcpAccountEditorPresentationCopyWith<$Res>? get acp;$AccountAcpKeyCopyWith<$Res>? get acpKey;

}
/// @nodoc
class _$AccountEditorViewStateCopyWithImpl<$Res>
    implements $AccountEditorViewStateCopyWith<$Res> {
  _$AccountEditorViewStateCopyWithImpl(this._self, this._then);

  final AccountEditorViewState _self;
  final $Res Function(AccountEditorViewState) _then;

/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? native = freezed,Object? acp = freezed,Object? acpKey = freezed,Object? loading = null,Object? dirty = null,Object? saving = null,Object? canSave = null,Object? draftRevision = null,Object? stale = null,Object? error = freezed,}) {
  return _then(AccountEditorViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountEditorKey,native: freezed == native ? _self.native : native // ignore: cast_nullable_to_non_nullable
as NativeAccountEditorPresentation?,acp: freezed == acp ? _self.acp : acp // ignore: cast_nullable_to_non_nullable
as AcpAccountEditorPresentation?,acpKey: freezed == acpKey ? _self.acpKey : acpKey // ignore: cast_nullable_to_non_nullable
as AccountAcpKey?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,canSave: null == canSave ? _self.canSave : canSave // ignore: cast_nullable_to_non_nullable
as bool,draftRevision: null == draftRevision ? _self.draftRevision : draftRevision // ignore: cast_nullable_to_non_nullable
as int,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEditorKeyCopyWith<$Res> get key {

  return $AccountEditorKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NativeAccountEditorPresentationCopyWith<$Res>? get native {
    if (_self.native == null) {
    return null;
  }

  return $NativeAccountEditorPresentationCopyWith<$Res>(_self.native!, (value) {
    return _then(_self.copyWith(native: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountEditorPresentationCopyWith<$Res>? get acp {
    if (_self.acp == null) {
    return null;
  }

  return $AcpAccountEditorPresentationCopyWith<$Res>(_self.acp!, (value) {
    return _then(_self.copyWith(acp: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountAcpKeyCopyWith<$Res>? get acpKey {
    if (_self.acpKey == null) {
    return null;
  }

  return $AccountAcpKeyCopyWith<$Res>(_self.acpKey!, (value) {
    return _then(_self.copyWith(acpKey: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountEditorViewState].
extension AccountEditorViewStatePatterns on AccountEditorViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountEditorViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountEditorViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountEditorViewState value)  $default,){
final _that = this;
switch (_that) {
case _AccountEditorViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountEditorViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AccountEditorViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountEditorKey key,  NativeAccountEditorPresentation? native,  AcpAccountEditorPresentation? acp,  AccountAcpKey? acpKey,  bool loading,  bool dirty,  bool saving,  bool canSave,  int draftRevision,  bool stale,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountEditorViewState() when $default != null:
return $default(_that.key,_that.native,_that.acp,_that.acpKey,_that.loading,_that.dirty,_that.saving,_that.canSave,_that.draftRevision,_that.stale,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountEditorKey key,  NativeAccountEditorPresentation? native,  AcpAccountEditorPresentation? acp,  AccountAcpKey? acpKey,  bool loading,  bool dirty,  bool saving,  bool canSave,  int draftRevision,  bool stale,  String? error)  $default,) {final _that = this;
switch (_that) {
case _AccountEditorViewState():
return $default(_that.key,_that.native,_that.acp,_that.acpKey,_that.loading,_that.dirty,_that.saving,_that.canSave,_that.draftRevision,_that.stale,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountEditorKey key,  NativeAccountEditorPresentation? native,  AcpAccountEditorPresentation? acp,  AccountAcpKey? acpKey,  bool loading,  bool dirty,  bool saving,  bool canSave,  int draftRevision,  bool stale,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _AccountEditorViewState() when $default != null:
return $default(_that.key,_that.native,_that.acp,_that.acpKey,_that.loading,_that.dirty,_that.saving,_that.canSave,_that.draftRevision,_that.stale,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _AccountEditorViewState implements AccountEditorViewState {
  const _AccountEditorViewState({required this.key, this.native, this.acp, this.acpKey, this.loading = false, this.dirty = false, this.saving = false, this.canSave = false, this.draftRevision = 0, this.stale = false, this.error});


@override final  AccountEditorKey key;
@override final  NativeAccountEditorPresentation? native;
@override final  AcpAccountEditorPresentation? acp;
@override final  AccountAcpKey? acpKey;
@override@JsonKey() final  bool loading;
@override@JsonKey() final  bool dirty;
@override@JsonKey() final  bool saving;
@override@JsonKey() final  bool canSave;
@override@JsonKey() final  int draftRevision;
@override@JsonKey() final  bool stale;
@override final  String? error;

/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountEditorViewStateCopyWith<_AccountEditorViewState> get copyWith => __$AccountEditorViewStateCopyWithImpl<_AccountEditorViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountEditorViewState&&(identical(other.key, key) || other.key == key)&&(identical(other.native, native) || other.native == native)&&(identical(other.acp, acp) || other.acp == acp)&&(identical(other.acpKey, acpKey) || other.acpKey == acpKey)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.saving, saving) || other.saving == saving)&&(identical(other.canSave, canSave) || other.canSave == canSave)&&(identical(other.draftRevision, draftRevision) || other.draftRevision == draftRevision)&&(identical(other.stale, stale) || other.stale == stale)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,native,acp,acpKey,loading,dirty,saving,canSave,draftRevision,stale,error);
}

@override
String toString() {
    return 'AccountEditorViewState(key: $key, native: $native, acp: $acp, acpKey: $acpKey, loading: $loading, dirty: $dirty, saving: $saving, canSave: $canSave, draftRevision: $draftRevision, stale: $stale, error: $error)';
}


}

/// @nodoc
abstract mixin class _$AccountEditorViewStateCopyWith<$Res> implements $AccountEditorViewStateCopyWith<$Res> {
  factory _$AccountEditorViewStateCopyWith(_AccountEditorViewState value, $Res Function(_AccountEditorViewState) _then) = __$AccountEditorViewStateCopyWithImpl;
@override @useResult
$Res call({
 AccountEditorKey key, NativeAccountEditorPresentation? native, AcpAccountEditorPresentation? acp, AccountAcpKey? acpKey, bool loading, bool dirty, bool saving, bool canSave, int draftRevision, bool stale, String? error
});


@override $AccountEditorKeyCopyWith<$Res> get key;@override $NativeAccountEditorPresentationCopyWith<$Res>? get native;@override $AcpAccountEditorPresentationCopyWith<$Res>? get acp;@override $AccountAcpKeyCopyWith<$Res>? get acpKey;

}
/// @nodoc
class __$AccountEditorViewStateCopyWithImpl<$Res>
    implements _$AccountEditorViewStateCopyWith<$Res> {
  __$AccountEditorViewStateCopyWithImpl(this._self, this._then);

  final _AccountEditorViewState _self;
  final $Res Function(_AccountEditorViewState) _then;

/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? native = freezed,Object? acp = freezed,Object? acpKey = freezed,Object? loading = null,Object? dirty = null,Object? saving = null,Object? canSave = null,Object? draftRevision = null,Object? stale = null,Object? error = freezed,}) {
  return _then(_AccountEditorViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountEditorKey,native: freezed == native ? _self.native : native // ignore: cast_nullable_to_non_nullable
as NativeAccountEditorPresentation?,acp: freezed == acp ? _self.acp : acp // ignore: cast_nullable_to_non_nullable
as AcpAccountEditorPresentation?,acpKey: freezed == acpKey ? _self.acpKey : acpKey // ignore: cast_nullable_to_non_nullable
as AccountAcpKey?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,canSave: null == canSave ? _self.canSave : canSave // ignore: cast_nullable_to_non_nullable
as bool,draftRevision: null == draftRevision ? _self.draftRevision : draftRevision // ignore: cast_nullable_to_non_nullable
as int,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEditorKeyCopyWith<$Res> get key {

  return $AccountEditorKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NativeAccountEditorPresentationCopyWith<$Res>? get native {
    if (_self.native == null) {
    return null;
  }

  return $NativeAccountEditorPresentationCopyWith<$Res>(_self.native!, (value) {
    return _then(_self.copyWith(native: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountEditorPresentationCopyWith<$Res>? get acp {
    if (_self.acp == null) {
    return null;
  }

  return $AcpAccountEditorPresentationCopyWith<$Res>(_self.acp!, (value) {
    return _then(_self.copyWith(acp: value));
  });
}/// Create a copy of AccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountAcpKeyCopyWith<$Res>? get acpKey {
    if (_self.acpKey == null) {
    return null;
  }

  return $AccountAcpKeyCopyWith<$Res>(_self.acpKey!, (value) {
    return _then(_self.copyWith(acpKey: value));
  });
}
}

/// @nodoc
mixin _$AccountAcpViewState {

 AcpAccountPresentation get panel; bool get preparedForEditor; String? get claimedOperationId; int get preparationGeneration;
/// Create a copy of AccountAcpViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountAcpViewStateCopyWith<AccountAcpViewState> get copyWith => _$AccountAcpViewStateCopyWithImpl<AccountAcpViewState>(this as AccountAcpViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountAcpViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountAcpViewState&&(identical(other.panel, _this.panel) || other.panel == _this.panel)&&(identical(other.preparedForEditor, _this.preparedForEditor) || other.preparedForEditor == _this.preparedForEditor)&&(identical(other.claimedOperationId, _this.claimedOperationId) || other.claimedOperationId == _this.claimedOperationId)&&(identical(other.preparationGeneration, _this.preparationGeneration) || other.preparationGeneration == _this.preparationGeneration));
}


@override
int get hashCode {
  final _this = this as AccountAcpViewState;
  return Object.hash(runtimeType,_this.panel,_this.preparedForEditor,_this.claimedOperationId,_this.preparationGeneration);
}

@override
String toString() {
  final _this = this as AccountAcpViewState;
  return 'AccountAcpViewState(panel: ${_this.panel}, preparedForEditor: ${_this.preparedForEditor}, claimedOperationId: ${_this.claimedOperationId}, preparationGeneration: ${_this.preparationGeneration})';
}


}

/// @nodoc
abstract mixin class $AccountAcpViewStateCopyWith<$Res>  {
  factory $AccountAcpViewStateCopyWith(AccountAcpViewState value, $Res Function(AccountAcpViewState) _then) = _$AccountAcpViewStateCopyWithImpl;
@useResult
$Res call({
 AcpAccountPresentation panel, bool preparedForEditor, String? claimedOperationId, int preparationGeneration
});


$AcpAccountPresentationCopyWith<$Res> get panel;

}
/// @nodoc
class _$AccountAcpViewStateCopyWithImpl<$Res>
    implements $AccountAcpViewStateCopyWith<$Res> {
  _$AccountAcpViewStateCopyWithImpl(this._self, this._then);

  final AccountAcpViewState _self;
  final $Res Function(AccountAcpViewState) _then;

/// Create a copy of AccountAcpViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? panel = null,Object? preparedForEditor = null,Object? claimedOperationId = freezed,Object? preparationGeneration = null,}) {
  return _then(AccountAcpViewState(
panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as AcpAccountPresentation,preparedForEditor: null == preparedForEditor ? _self.preparedForEditor : preparedForEditor // ignore: cast_nullable_to_non_nullable
as bool,claimedOperationId: freezed == claimedOperationId ? _self.claimedOperationId : claimedOperationId // ignore: cast_nullable_to_non_nullable
as String?,preparationGeneration: null == preparationGeneration ? _self.preparationGeneration : preparationGeneration // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AccountAcpViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountPresentationCopyWith<$Res> get panel {

  return $AcpAccountPresentationCopyWith<$Res>(_self.panel, (value) {
    return _then(_self.copyWith(panel: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountAcpViewState].
extension AccountAcpViewStatePatterns on AccountAcpViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountAcpViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountAcpViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountAcpViewState value)  $default,){
final _that = this;
switch (_that) {
case _AccountAcpViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountAcpViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AccountAcpViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AcpAccountPresentation panel,  bool preparedForEditor,  String? claimedOperationId,  int preparationGeneration)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountAcpViewState() when $default != null:
return $default(_that.panel,_that.preparedForEditor,_that.claimedOperationId,_that.preparationGeneration);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AcpAccountPresentation panel,  bool preparedForEditor,  String? claimedOperationId,  int preparationGeneration)  $default,) {final _that = this;
switch (_that) {
case _AccountAcpViewState():
return $default(_that.panel,_that.preparedForEditor,_that.claimedOperationId,_that.preparationGeneration);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AcpAccountPresentation panel,  bool preparedForEditor,  String? claimedOperationId,  int preparationGeneration)?  $default,) {final _that = this;
switch (_that) {
case _AccountAcpViewState() when $default != null:
return $default(_that.panel,_that.preparedForEditor,_that.claimedOperationId,_that.preparationGeneration);case _:
  return null;

}
}

}

/// @nodoc


class _AccountAcpViewState implements AccountAcpViewState {
  const _AccountAcpViewState({required this.panel, this.preparedForEditor = false, this.claimedOperationId, this.preparationGeneration = 0});


@override final  AcpAccountPresentation panel;
@override@JsonKey() final  bool preparedForEditor;
@override final  String? claimedOperationId;
@override@JsonKey() final  int preparationGeneration;

/// Create a copy of AccountAcpViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountAcpViewStateCopyWith<_AccountAcpViewState> get copyWith => __$AccountAcpViewStateCopyWithImpl<_AccountAcpViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountAcpViewState&&(identical(other.panel, panel) || other.panel == panel)&&(identical(other.preparedForEditor, preparedForEditor) || other.preparedForEditor == preparedForEditor)&&(identical(other.claimedOperationId, claimedOperationId) || other.claimedOperationId == claimedOperationId)&&(identical(other.preparationGeneration, preparationGeneration) || other.preparationGeneration == preparationGeneration));
}


@override
int get hashCode {
    return Object.hash(runtimeType,panel,preparedForEditor,claimedOperationId,preparationGeneration);
}

@override
String toString() {
    return 'AccountAcpViewState(panel: $panel, preparedForEditor: $preparedForEditor, claimedOperationId: $claimedOperationId, preparationGeneration: $preparationGeneration)';
}


}

/// @nodoc
abstract mixin class _$AccountAcpViewStateCopyWith<$Res> implements $AccountAcpViewStateCopyWith<$Res> {
  factory _$AccountAcpViewStateCopyWith(_AccountAcpViewState value, $Res Function(_AccountAcpViewState) _then) = __$AccountAcpViewStateCopyWithImpl;
@override @useResult
$Res call({
 AcpAccountPresentation panel, bool preparedForEditor, String? claimedOperationId, int preparationGeneration
});


@override $AcpAccountPresentationCopyWith<$Res> get panel;

}
/// @nodoc
class __$AccountAcpViewStateCopyWithImpl<$Res>
    implements _$AccountAcpViewStateCopyWith<$Res> {
  __$AccountAcpViewStateCopyWithImpl(this._self, this._then);

  final _AccountAcpViewState _self;
  final $Res Function(_AccountAcpViewState) _then;

/// Create a copy of AccountAcpViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? panel = null,Object? preparedForEditor = null,Object? claimedOperationId = freezed,Object? preparationGeneration = null,}) {
  return _then(_AccountAcpViewState(
panel: null == panel ? _self.panel : panel // ignore: cast_nullable_to_non_nullable
as AcpAccountPresentation,preparedForEditor: null == preparedForEditor ? _self.preparedForEditor : preparedForEditor // ignore: cast_nullable_to_non_nullable
as bool,claimedOperationId: freezed == claimedOperationId ? _self.claimedOperationId : claimedOperationId // ignore: cast_nullable_to_non_nullable
as String?,preparationGeneration: null == preparationGeneration ? _self.preparationGeneration : preparationGeneration // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AccountAcpViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountPresentationCopyWith<$Res> get panel {

  return $AcpAccountPresentationCopyWith<$Res>(_self.panel, (value) {
    return _then(_self.copyWith(panel: value));
  });
}
}

// dart format on
