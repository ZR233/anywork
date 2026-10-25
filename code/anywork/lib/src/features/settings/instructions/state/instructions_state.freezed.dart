// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'instructions_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InstructionDraft {

 String get raw; int get revision; bool get dirty; SettingsAction? get action;
/// Create a copy of InstructionDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstructionDraftCopyWith<InstructionDraft> get copyWith => _$InstructionDraftCopyWithImpl<InstructionDraft>(this as InstructionDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InstructionDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstructionDraft&&(identical(other.raw, _this.raw) || other.raw == _this.raw)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&(identical(other.action, _this.action) || other.action == _this.action));
}


@override
int get hashCode {
  final _this = this as InstructionDraft;
  return Object.hash(runtimeType,_this.raw,_this.revision,_this.dirty,_this.action);
}



}

/// @nodoc
abstract mixin class $InstructionDraftCopyWith<$Res>  {
  factory $InstructionDraftCopyWith(InstructionDraft value, $Res Function(InstructionDraft) _then) = _$InstructionDraftCopyWithImpl;
@useResult
$Res call({
 String raw, int revision, bool dirty, SettingsAction? action
});


$SettingsActionCopyWith<$Res>? get action;

}
/// @nodoc
class _$InstructionDraftCopyWithImpl<$Res>
    implements $InstructionDraftCopyWith<$Res> {
  _$InstructionDraftCopyWithImpl(this._self, this._then);

  final InstructionDraft _self;
  final $Res Function(InstructionDraft) _then;

/// Create a copy of InstructionDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? raw = null,Object? revision = null,Object? dirty = null,Object? action = freezed,}) {
  return _then(InstructionDraft(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}
/// Create a copy of InstructionDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get action {
    if (_self.action == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.action!, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}


/// Adds pattern-matching-related methods to [InstructionDraft].
extension InstructionDraftPatterns on InstructionDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InstructionDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InstructionDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InstructionDraft value)  $default,){
final _that = this;
switch (_that) {
case _InstructionDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InstructionDraft value)?  $default,){
final _that = this;
switch (_that) {
case _InstructionDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String raw,  int revision,  bool dirty,  SettingsAction? action)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InstructionDraft() when $default != null:
return $default(_that.raw,_that.revision,_that.dirty,_that.action);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String raw,  int revision,  bool dirty,  SettingsAction? action)  $default,) {final _that = this;
switch (_that) {
case _InstructionDraft():
return $default(_that.raw,_that.revision,_that.dirty,_that.action);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String raw,  int revision,  bool dirty,  SettingsAction? action)?  $default,) {final _that = this;
switch (_that) {
case _InstructionDraft() when $default != null:
return $default(_that.raw,_that.revision,_that.dirty,_that.action);case _:
  return null;

}
}

}

/// @nodoc


class _InstructionDraft implements InstructionDraft {
  const _InstructionDraft({required this.raw, this.revision = 0, this.dirty = false, this.action});


@override final  String raw;
@override@JsonKey() final  int revision;
@override@JsonKey() final  bool dirty;
@override final  SettingsAction? action;

/// Create a copy of InstructionDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InstructionDraftCopyWith<_InstructionDraft> get copyWith => __$InstructionDraftCopyWithImpl<_InstructionDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InstructionDraft&&(identical(other.raw, raw) || other.raw == raw)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.action, action) || other.action == action));
}


@override
int get hashCode {
    return Object.hash(runtimeType,raw,revision,dirty,action);
}



}

/// @nodoc
abstract mixin class _$InstructionDraftCopyWith<$Res> implements $InstructionDraftCopyWith<$Res> {
  factory _$InstructionDraftCopyWith(_InstructionDraft value, $Res Function(_InstructionDraft) _then) = __$InstructionDraftCopyWithImpl;
@override @useResult
$Res call({
 String raw, int revision, bool dirty, SettingsAction? action
});


@override $SettingsActionCopyWith<$Res>? get action;

}
/// @nodoc
class __$InstructionDraftCopyWithImpl<$Res>
    implements _$InstructionDraftCopyWith<$Res> {
  __$InstructionDraftCopyWithImpl(this._self, this._then);

  final _InstructionDraft _self;
  final $Res Function(_InstructionDraft) _then;

/// Create a copy of InstructionDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? raw = null,Object? revision = null,Object? dirty = null,Object? action = freezed,}) {
  return _then(_InstructionDraft(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SettingsAction?,
  ));
}

/// Create a copy of InstructionDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get action {
    if (_self.action == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.action!, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}

/// @nodoc
mixin _$InstructionsViewState {

 ConfigurationState get source; InstructionsSettings get canonical; InstructionDraft get base; InstructionDraft get developer; InstructionDraft get user; InstructionSection get section; Map<InstructionsReadField, StudioFailure> get readIssues; bool get readPending;
/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstructionsViewStateCopyWith<InstructionsViewState> get copyWith => _$InstructionsViewStateCopyWithImpl<InstructionsViewState>(this as InstructionsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InstructionsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstructionsViewState&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.canonical, _this.canonical) || other.canonical == _this.canonical)&&(identical(other.base, _this.base) || other.base == _this.base)&&(identical(other.developer, _this.developer) || other.developer == _this.developer)&&(identical(other.user, _this.user) || other.user == _this.user)&&(identical(other.section, _this.section) || other.section == _this.section)&&const DeepCollectionEquality().equals(other.readIssues, _this.readIssues)&&(identical(other.readPending, _this.readPending) || other.readPending == _this.readPending));
}


@override
int get hashCode {
  final _this = this as InstructionsViewState;
  return Object.hash(runtimeType,_this.source,_this.canonical,_this.base,_this.developer,_this.user,_this.section,const DeepCollectionEquality().hash(_this.readIssues),_this.readPending);
}



}

/// @nodoc
abstract mixin class $InstructionsViewStateCopyWith<$Res>  {
  factory $InstructionsViewStateCopyWith(InstructionsViewState value, $Res Function(InstructionsViewState) _then) = _$InstructionsViewStateCopyWithImpl;
@useResult
$Res call({
 ConfigurationState source, InstructionsSettings canonical, InstructionDraft base, InstructionDraft developer, InstructionDraft user, InstructionSection section, Map<InstructionsReadField, StudioFailure> readIssues, bool readPending
});


$ConfigurationStateCopyWith<$Res> get source;$InstructionsSettingsCopyWith<$Res> get canonical;$InstructionDraftCopyWith<$Res> get base;$InstructionDraftCopyWith<$Res> get developer;$InstructionDraftCopyWith<$Res> get user;

}
/// @nodoc
class _$InstructionsViewStateCopyWithImpl<$Res>
    implements $InstructionsViewStateCopyWith<$Res> {
  _$InstructionsViewStateCopyWithImpl(this._self, this._then);

  final InstructionsViewState _self;
  final $Res Function(InstructionsViewState) _then;

/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? canonical = null,Object? base = null,Object? developer = null,Object? user = null,Object? section = null,Object? readIssues = null,Object? readPending = null,}) {
  return _then(InstructionsViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,canonical: null == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as InstructionsSettings,base: null == base ? _self.base : base // ignore: cast_nullable_to_non_nullable
as InstructionDraft,developer: null == developer ? _self.developer : developer // ignore: cast_nullable_to_non_nullable
as InstructionDraft,user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as InstructionDraft,section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as InstructionSection,readIssues: null == readIssues ? _self.readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<InstructionsReadField, StudioFailure>,readPending: null == readPending ? _self.readPending : readPending // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionsSettingsCopyWith<$Res> get canonical {

  return $InstructionsSettingsCopyWith<$Res>(_self.canonical, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionDraftCopyWith<$Res> get base {

  return $InstructionDraftCopyWith<$Res>(_self.base, (value) {
    return _then(_self.copyWith(base: value));
  });
}/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionDraftCopyWith<$Res> get developer {

  return $InstructionDraftCopyWith<$Res>(_self.developer, (value) {
    return _then(_self.copyWith(developer: value));
  });
}/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionDraftCopyWith<$Res> get user {

  return $InstructionDraftCopyWith<$Res>(_self.user, (value) {
    return _then(_self.copyWith(user: value));
  });
}
}


/// Adds pattern-matching-related methods to [InstructionsViewState].
extension InstructionsViewStatePatterns on InstructionsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InstructionsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InstructionsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InstructionsViewState value)  $default,){
final _that = this;
switch (_that) {
case _InstructionsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InstructionsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _InstructionsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigurationState source,  InstructionsSettings canonical,  InstructionDraft base,  InstructionDraft developer,  InstructionDraft user,  InstructionSection section,  Map<InstructionsReadField, StudioFailure> readIssues,  bool readPending)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InstructionsViewState() when $default != null:
return $default(_that.source,_that.canonical,_that.base,_that.developer,_that.user,_that.section,_that.readIssues,_that.readPending);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigurationState source,  InstructionsSettings canonical,  InstructionDraft base,  InstructionDraft developer,  InstructionDraft user,  InstructionSection section,  Map<InstructionsReadField, StudioFailure> readIssues,  bool readPending)  $default,) {final _that = this;
switch (_that) {
case _InstructionsViewState():
return $default(_that.source,_that.canonical,_that.base,_that.developer,_that.user,_that.section,_that.readIssues,_that.readPending);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigurationState source,  InstructionsSettings canonical,  InstructionDraft base,  InstructionDraft developer,  InstructionDraft user,  InstructionSection section,  Map<InstructionsReadField, StudioFailure> readIssues,  bool readPending)?  $default,) {final _that = this;
switch (_that) {
case _InstructionsViewState() when $default != null:
return $default(_that.source,_that.canonical,_that.base,_that.developer,_that.user,_that.section,_that.readIssues,_that.readPending);case _:
  return null;

}
}

}

/// @nodoc


class _InstructionsViewState implements InstructionsViewState {
  const _InstructionsViewState({required this.source, required this.canonical, required this.base, required this.developer, required this.user, this.section = InstructionSection.base,  Map<InstructionsReadField, StudioFailure> readIssues = const {}, this.readPending = false}): _readIssues = readIssues;


@override final  ConfigurationState source;
@override final  InstructionsSettings canonical;
@override final  InstructionDraft base;
@override final  InstructionDraft developer;
@override final  InstructionDraft user;
@override@JsonKey() final  InstructionSection section;
 final  Map<InstructionsReadField, StudioFailure> _readIssues;
@override@JsonKey() Map<InstructionsReadField, StudioFailure> get readIssues {
  if (_readIssues is EqualUnmodifiableMapView) return _readIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readIssues);
}

@override@JsonKey() final  bool readPending;

/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InstructionsViewStateCopyWith<_InstructionsViewState> get copyWith => __$InstructionsViewStateCopyWithImpl<_InstructionsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InstructionsViewState&&(identical(other.source, source) || other.source == source)&&(identical(other.canonical, canonical) || other.canonical == canonical)&&(identical(other.base, base) || other.base == base)&&(identical(other.developer, developer) || other.developer == developer)&&(identical(other.user, user) || other.user == user)&&(identical(other.section, section) || other.section == section)&&const DeepCollectionEquality().equals(other.readIssues, _readIssues)&&(identical(other.readPending, readPending) || other.readPending == readPending));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,canonical,base,developer,user,section,const DeepCollectionEquality().hash(_readIssues),readPending);
}



}

/// @nodoc
abstract mixin class _$InstructionsViewStateCopyWith<$Res> implements $InstructionsViewStateCopyWith<$Res> {
  factory _$InstructionsViewStateCopyWith(_InstructionsViewState value, $Res Function(_InstructionsViewState) _then) = __$InstructionsViewStateCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationState source, InstructionsSettings canonical, InstructionDraft base, InstructionDraft developer, InstructionDraft user, InstructionSection section, Map<InstructionsReadField, StudioFailure> readIssues, bool readPending
});


@override $ConfigurationStateCopyWith<$Res> get source;@override $InstructionsSettingsCopyWith<$Res> get canonical;@override $InstructionDraftCopyWith<$Res> get base;@override $InstructionDraftCopyWith<$Res> get developer;@override $InstructionDraftCopyWith<$Res> get user;

}
/// @nodoc
class __$InstructionsViewStateCopyWithImpl<$Res>
    implements _$InstructionsViewStateCopyWith<$Res> {
  __$InstructionsViewStateCopyWithImpl(this._self, this._then);

  final _InstructionsViewState _self;
  final $Res Function(_InstructionsViewState) _then;

/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? canonical = null,Object? base = null,Object? developer = null,Object? user = null,Object? section = null,Object? readIssues = null,Object? readPending = null,}) {
  return _then(_InstructionsViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ConfigurationState,canonical: null == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as InstructionsSettings,base: null == base ? _self.base : base // ignore: cast_nullable_to_non_nullable
as InstructionDraft,developer: null == developer ? _self.developer : developer // ignore: cast_nullable_to_non_nullable
as InstructionDraft,user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as InstructionDraft,section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as InstructionSection,readIssues: null == readIssues ? _self._readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<InstructionsReadField, StudioFailure>,readPending: null == readPending ? _self.readPending : readPending // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get source {

  return $ConfigurationStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionsSettingsCopyWith<$Res> get canonical {

  return $InstructionsSettingsCopyWith<$Res>(_self.canonical, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionDraftCopyWith<$Res> get base {

  return $InstructionDraftCopyWith<$Res>(_self.base, (value) {
    return _then(_self.copyWith(base: value));
  });
}/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionDraftCopyWith<$Res> get developer {

  return $InstructionDraftCopyWith<$Res>(_self.developer, (value) {
    return _then(_self.copyWith(developer: value));
  });
}/// Create a copy of InstructionsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InstructionDraftCopyWith<$Res> get user {

  return $InstructionDraftCopyWith<$Res>(_self.user, (value) {
    return _then(_self.copyWith(user: value));
  });
}
}

// dart format on
