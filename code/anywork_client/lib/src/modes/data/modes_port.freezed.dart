// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'modes_port.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModeDefinitionCommandReply {

 ModeCatalogReadTarget get catalog; ModeDefinitionSnapshot? get definition; CommitReceipt get receipt;
/// Create a copy of ModeDefinitionCommandReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeDefinitionCommandReplyCopyWith<ModeDefinitionCommandReply> get copyWith => _$ModeDefinitionCommandReplyCopyWithImpl<ModeDefinitionCommandReply>(this as ModeDefinitionCommandReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeDefinitionCommandReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeDefinitionCommandReply&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog)&&(identical(other.definition, _this.definition) || other.definition == _this.definition)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as ModeDefinitionCommandReply;
  return Object.hash(runtimeType,_this.catalog,_this.definition,_this.receipt);
}



}

/// @nodoc
abstract mixin class $ModeDefinitionCommandReplyCopyWith<$Res>  {
  factory $ModeDefinitionCommandReplyCopyWith(ModeDefinitionCommandReply value, $Res Function(ModeDefinitionCommandReply) _then) = _$ModeDefinitionCommandReplyCopyWithImpl;
@useResult
$Res call({
 ModeCatalogReadTarget catalog, ModeDefinitionSnapshot? definition, CommitReceipt receipt
});


$ModeCatalogReadTargetCopyWith<$Res> get catalog;$ModeDefinitionSnapshotCopyWith<$Res>? get definition;$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$ModeDefinitionCommandReplyCopyWithImpl<$Res>
    implements $ModeDefinitionCommandReplyCopyWith<$Res> {
  _$ModeDefinitionCommandReplyCopyWithImpl(this._self, this._then);

  final ModeDefinitionCommandReply _self;
  final $Res Function(ModeDefinitionCommandReply) _then;

/// Create a copy of ModeDefinitionCommandReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? catalog = null,Object? definition = freezed,Object? receipt = null,}) {
  return _then(ModeDefinitionCommandReply(
catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModeCatalogReadTarget,definition: freezed == definition ? _self.definition : definition // ignore: cast_nullable_to_non_nullable
as ModeDefinitionSnapshot?,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}
/// Create a copy of ModeDefinitionCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogReadTargetCopyWith<$Res> get catalog {

  return $ModeCatalogReadTargetCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ModeDefinitionCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDefinitionSnapshotCopyWith<$Res>? get definition {
    if (_self.definition == null) {
    return null;
  }

  return $ModeDefinitionSnapshotCopyWith<$Res>(_self.definition!, (value) {
    return _then(_self.copyWith(definition: value));
  });
}/// Create a copy of ModeDefinitionCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeDefinitionCommandReply].
extension ModeDefinitionCommandReplyPatterns on ModeDefinitionCommandReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeDefinitionCommandReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeDefinitionCommandReply() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeDefinitionCommandReply value)  $default,){
final _that = this;
switch (_that) {
case _ModeDefinitionCommandReply():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeDefinitionCommandReply value)?  $default,){
final _that = this;
switch (_that) {
case _ModeDefinitionCommandReply() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModeCatalogReadTarget catalog,  ModeDefinitionSnapshot? definition,  CommitReceipt receipt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeDefinitionCommandReply() when $default != null:
return $default(_that.catalog,_that.definition,_that.receipt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModeCatalogReadTarget catalog,  ModeDefinitionSnapshot? definition,  CommitReceipt receipt)  $default,) {final _that = this;
switch (_that) {
case _ModeDefinitionCommandReply():
return $default(_that.catalog,_that.definition,_that.receipt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModeCatalogReadTarget catalog,  ModeDefinitionSnapshot? definition,  CommitReceipt receipt)?  $default,) {final _that = this;
switch (_that) {
case _ModeDefinitionCommandReply() when $default != null:
return $default(_that.catalog,_that.definition,_that.receipt);case _:
  return null;

}
}

}

/// @nodoc


class _ModeDefinitionCommandReply implements ModeDefinitionCommandReply {
  const _ModeDefinitionCommandReply({required this.catalog, required this.definition, required this.receipt});


@override final  ModeCatalogReadTarget catalog;
@override final  ModeDefinitionSnapshot? definition;
@override final  CommitReceipt receipt;

/// Create a copy of ModeDefinitionCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeDefinitionCommandReplyCopyWith<_ModeDefinitionCommandReply> get copyWith => __$ModeDefinitionCommandReplyCopyWithImpl<_ModeDefinitionCommandReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeDefinitionCommandReply&&(identical(other.catalog, catalog) || other.catalog == catalog)&&(identical(other.definition, definition) || other.definition == definition)&&(identical(other.receipt, receipt) || other.receipt == receipt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,catalog,definition,receipt);
}



}

/// @nodoc
abstract mixin class _$ModeDefinitionCommandReplyCopyWith<$Res> implements $ModeDefinitionCommandReplyCopyWith<$Res> {
  factory _$ModeDefinitionCommandReplyCopyWith(_ModeDefinitionCommandReply value, $Res Function(_ModeDefinitionCommandReply) _then) = __$ModeDefinitionCommandReplyCopyWithImpl;
@override @useResult
$Res call({
 ModeCatalogReadTarget catalog, ModeDefinitionSnapshot? definition, CommitReceipt receipt
});


@override $ModeCatalogReadTargetCopyWith<$Res> get catalog;@override $ModeDefinitionSnapshotCopyWith<$Res>? get definition;@override $CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class __$ModeDefinitionCommandReplyCopyWithImpl<$Res>
    implements _$ModeDefinitionCommandReplyCopyWith<$Res> {
  __$ModeDefinitionCommandReplyCopyWithImpl(this._self, this._then);

  final _ModeDefinitionCommandReply _self;
  final $Res Function(_ModeDefinitionCommandReply) _then;

/// Create a copy of ModeDefinitionCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? catalog = null,Object? definition = freezed,Object? receipt = null,}) {
  return _then(_ModeDefinitionCommandReply(
catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModeCatalogReadTarget,definition: freezed == definition ? _self.definition : definition // ignore: cast_nullable_to_non_nullable
as ModeDefinitionSnapshot?,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}

/// Create a copy of ModeDefinitionCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogReadTargetCopyWith<$Res> get catalog {

  return $ModeCatalogReadTargetCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ModeDefinitionCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDefinitionSnapshotCopyWith<$Res>? get definition {
    if (_self.definition == null) {
    return null;
  }

  return $ModeDefinitionSnapshotCopyWith<$Res>(_self.definition!, (value) {
    return _then(_self.copyWith(definition: value));
  });
}/// Create a copy of ModeDefinitionCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}

/// @nodoc
mixin _$ModeCatalogReadHeader {

 int get revision; TypedListRef get modes;
/// Create a copy of ModeCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogReadHeaderCopyWith<ModeCatalogReadHeader> get copyWith => _$ModeCatalogReadHeaderCopyWithImpl<ModeCatalogReadHeader>(this as ModeCatalogReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeCatalogReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogReadHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.modes, _this.modes) || other.modes == _this.modes));
}


@override
int get hashCode {
  final _this = this as ModeCatalogReadHeader;
  return Object.hash(runtimeType,_this.revision,_this.modes);
}

@override
String toString() {
  final _this = this as ModeCatalogReadHeader;
  return 'ModeCatalogReadHeader(revision: ${_this.revision}, modes: ${_this.modes})';
}


}

/// @nodoc
abstract mixin class $ModeCatalogReadHeaderCopyWith<$Res>  {
  factory $ModeCatalogReadHeaderCopyWith(ModeCatalogReadHeader value, $Res Function(ModeCatalogReadHeader) _then) = _$ModeCatalogReadHeaderCopyWithImpl;
@useResult
$Res call({
 int revision, TypedListRef modes
});


$TypedListRefCopyWith<$Res> get modes;

}
/// @nodoc
class _$ModeCatalogReadHeaderCopyWithImpl<$Res>
    implements $ModeCatalogReadHeaderCopyWith<$Res> {
  _$ModeCatalogReadHeaderCopyWithImpl(this._self, this._then);

  final ModeCatalogReadHeader _self;
  final $Res Function(ModeCatalogReadHeader) _then;

/// Create a copy of ModeCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? modes = null,}) {
  return _then(ModeCatalogReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,modes: null == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of ModeCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get modes {

  return $TypedListRefCopyWith<$Res>(_self.modes, (value) {
    return _then(_self.copyWith(modes: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeCatalogReadHeader].
extension ModeCatalogReadHeaderPatterns on ModeCatalogReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeCatalogReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeCatalogReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeCatalogReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeCatalogReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  TypedListRef modes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeCatalogReadHeader() when $default != null:
return $default(_that.revision,_that.modes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  TypedListRef modes)  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogReadHeader():
return $default(_that.revision,_that.modes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  TypedListRef modes)?  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogReadHeader() when $default != null:
return $default(_that.revision,_that.modes);case _:
  return null;

}
}

}

/// @nodoc


class _ModeCatalogReadHeader implements ModeCatalogReadHeader {
  const _ModeCatalogReadHeader({required this.revision, required this.modes});


@override final  int revision;
@override final  TypedListRef modes;

/// Create a copy of ModeCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeCatalogReadHeaderCopyWith<_ModeCatalogReadHeader> get copyWith => __$ModeCatalogReadHeaderCopyWithImpl<_ModeCatalogReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeCatalogReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.modes, modes) || other.modes == modes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,modes);
}

@override
String toString() {
    return 'ModeCatalogReadHeader(revision: $revision, modes: $modes)';
}


}

/// @nodoc
abstract mixin class _$ModeCatalogReadHeaderCopyWith<$Res> implements $ModeCatalogReadHeaderCopyWith<$Res> {
  factory _$ModeCatalogReadHeaderCopyWith(_ModeCatalogReadHeader value, $Res Function(_ModeCatalogReadHeader) _then) = __$ModeCatalogReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, TypedListRef modes
});


@override $TypedListRefCopyWith<$Res> get modes;

}
/// @nodoc
class __$ModeCatalogReadHeaderCopyWithImpl<$Res>
    implements _$ModeCatalogReadHeaderCopyWith<$Res> {
  __$ModeCatalogReadHeaderCopyWithImpl(this._self, this._then);

  final _ModeCatalogReadHeader _self;
  final $Res Function(_ModeCatalogReadHeader) _then;

/// Create a copy of ModeCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? modes = null,}) {
  return _then(_ModeCatalogReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,modes: null == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of ModeCatalogReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get modes {

  return $TypedListRefCopyWith<$Res>(_self.modes, (value) {
    return _then(_self.copyWith(modes: value));
  });
}
}

/// @nodoc
mixin _$ThreadModeDescriptorRead {

 ThreadModeId get id; ReadText get displayName; ReadText get description; int get order; bool get hasWorkflow; bool get readOnly;
/// Create a copy of ThreadModeDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadModeDescriptorReadCopyWith<ThreadModeDescriptorRead> get copyWith => _$ThreadModeDescriptorReadCopyWithImpl<ThreadModeDescriptorRead>(this as ThreadModeDescriptorRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadModeDescriptorRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadModeDescriptorRead&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.order, _this.order) || other.order == _this.order)&&(identical(other.hasWorkflow, _this.hasWorkflow) || other.hasWorkflow == _this.hasWorkflow)&&(identical(other.readOnly, _this.readOnly) || other.readOnly == _this.readOnly));
}


@override
int get hashCode {
  final _this = this as ThreadModeDescriptorRead;
  return Object.hash(runtimeType,_this.id,_this.displayName,_this.description,_this.order,_this.hasWorkflow,_this.readOnly);
}



}

/// @nodoc
abstract mixin class $ThreadModeDescriptorReadCopyWith<$Res>  {
  factory $ThreadModeDescriptorReadCopyWith(ThreadModeDescriptorRead value, $Res Function(ThreadModeDescriptorRead) _then) = _$ThreadModeDescriptorReadCopyWithImpl;
@useResult
$Res call({
 ThreadModeId id, ReadText displayName, ReadText description, int order, bool hasWorkflow, bool readOnly
});


$ReadTextCopyWith<$Res> get displayName;$ReadTextCopyWith<$Res> get description;

}
/// @nodoc
class _$ThreadModeDescriptorReadCopyWithImpl<$Res>
    implements $ThreadModeDescriptorReadCopyWith<$Res> {
  _$ThreadModeDescriptorReadCopyWithImpl(this._self, this._then);

  final ThreadModeDescriptorRead _self;
  final $Res Function(ThreadModeDescriptorRead) _then;

/// Create a copy of ThreadModeDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? description = null,Object? order = null,Object? hasWorkflow = null,Object? readOnly = null,}) {
  return _then(ThreadModeDescriptorRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ThreadModeId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,hasWorkflow: null == hasWorkflow ? _self.hasWorkflow : hasWorkflow // ignore: cast_nullable_to_non_nullable
as bool,readOnly: null == readOnly ? _self.readOnly : readOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ThreadModeDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of ThreadModeDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get description {

  return $ReadTextCopyWith<$Res>(_self.description, (value) {
    return _then(_self.copyWith(description: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadModeDescriptorRead].
extension ThreadModeDescriptorReadPatterns on ThreadModeDescriptorRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadModeDescriptorRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadModeDescriptorRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadModeDescriptorRead value)  $default,){
final _that = this;
switch (_that) {
case _ThreadModeDescriptorRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadModeDescriptorRead value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadModeDescriptorRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadModeId id,  ReadText displayName,  ReadText description,  int order,  bool hasWorkflow,  bool readOnly)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadModeDescriptorRead() when $default != null:
return $default(_that.id,_that.displayName,_that.description,_that.order,_that.hasWorkflow,_that.readOnly);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadModeId id,  ReadText displayName,  ReadText description,  int order,  bool hasWorkflow,  bool readOnly)  $default,) {final _that = this;
switch (_that) {
case _ThreadModeDescriptorRead():
return $default(_that.id,_that.displayName,_that.description,_that.order,_that.hasWorkflow,_that.readOnly);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadModeId id,  ReadText displayName,  ReadText description,  int order,  bool hasWorkflow,  bool readOnly)?  $default,) {final _that = this;
switch (_that) {
case _ThreadModeDescriptorRead() when $default != null:
return $default(_that.id,_that.displayName,_that.description,_that.order,_that.hasWorkflow,_that.readOnly);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadModeDescriptorRead implements ThreadModeDescriptorRead {
  const _ThreadModeDescriptorRead({required this.id, required this.displayName, required this.description, required this.order, required this.hasWorkflow, required this.readOnly});


@override final  ThreadModeId id;
@override final  ReadText displayName;
@override final  ReadText description;
@override final  int order;
@override final  bool hasWorkflow;
@override final  bool readOnly;

/// Create a copy of ThreadModeDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadModeDescriptorReadCopyWith<_ThreadModeDescriptorRead> get copyWith => __$ThreadModeDescriptorReadCopyWithImpl<_ThreadModeDescriptorRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadModeDescriptorRead&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.order, order) || other.order == order)&&(identical(other.hasWorkflow, hasWorkflow) || other.hasWorkflow == hasWorkflow)&&(identical(other.readOnly, readOnly) || other.readOnly == readOnly));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName,description,order,hasWorkflow,readOnly);
}



}

/// @nodoc
abstract mixin class _$ThreadModeDescriptorReadCopyWith<$Res> implements $ThreadModeDescriptorReadCopyWith<$Res> {
  factory _$ThreadModeDescriptorReadCopyWith(_ThreadModeDescriptorRead value, $Res Function(_ThreadModeDescriptorRead) _then) = __$ThreadModeDescriptorReadCopyWithImpl;
@override @useResult
$Res call({
 ThreadModeId id, ReadText displayName, ReadText description, int order, bool hasWorkflow, bool readOnly
});


@override $ReadTextCopyWith<$Res> get displayName;@override $ReadTextCopyWith<$Res> get description;

}
/// @nodoc
class __$ThreadModeDescriptorReadCopyWithImpl<$Res>
    implements _$ThreadModeDescriptorReadCopyWith<$Res> {
  __$ThreadModeDescriptorReadCopyWithImpl(this._self, this._then);

  final _ThreadModeDescriptorRead _self;
  final $Res Function(_ThreadModeDescriptorRead) _then;

/// Create a copy of ThreadModeDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? description = null,Object? order = null,Object? hasWorkflow = null,Object? readOnly = null,}) {
  return _then(_ThreadModeDescriptorRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ThreadModeId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,hasWorkflow: null == hasWorkflow ? _self.hasWorkflow : hasWorkflow // ignore: cast_nullable_to_non_nullable
as bool,readOnly: null == readOnly ? _self.readOnly : readOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ThreadModeDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of ThreadModeDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get description {

  return $ReadTextCopyWith<$Res>(_self.description, (value) {
    return _then(_self.copyWith(description: value));
  });
}
}

/// @nodoc
mixin _$ModeCatalogEntryPage {

 ProductCollectionRef get collection; int get offset; List<ProductEntityRef> get items; int? get nextOffset;
/// Create a copy of ModeCatalogEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogEntryPageCopyWith<ModeCatalogEntryPage> get copyWith => _$ModeCatalogEntryPageCopyWithImpl<ModeCatalogEntryPage>(this as ModeCatalogEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeCatalogEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as ModeCatalogEntryPage;
  return Object.hash(runtimeType,_this.collection,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as ModeCatalogEntryPage;
  return 'ModeCatalogEntryPage(collection: ${_this.collection}, offset: ${_this.offset}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $ModeCatalogEntryPageCopyWith<$Res>  {
  factory $ModeCatalogEntryPageCopyWith(ModeCatalogEntryPage value, $Res Function(ModeCatalogEntryPage) _then) = _$ModeCatalogEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


$ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class _$ModeCatalogEntryPageCopyWithImpl<$Res>
    implements $ModeCatalogEntryPageCopyWith<$Res> {
  _$ModeCatalogEntryPageCopyWithImpl(this._self, this._then);

  final ModeCatalogEntryPage _self;
  final $Res Function(ModeCatalogEntryPage) _then;

/// Create a copy of ModeCatalogEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(ModeCatalogEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of ModeCatalogEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeCatalogEntryPage].
extension ModeCatalogEntryPagePatterns on ModeCatalogEntryPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeCatalogEntryPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeCatalogEntryPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeCatalogEntryPage value)  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogEntryPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeCatalogEntryPage value)?  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogEntryPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeCatalogEntryPage() when $default != null:
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogEntryPage():
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogEntryPage() when $default != null:
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _ModeCatalogEntryPage implements ModeCatalogEntryPage {
  const _ModeCatalogEntryPage({required this.collection, required this.offset, required  List<ProductEntityRef> items, required this.nextOffset}): _items = items;


@override final  ProductCollectionRef collection;
@override final  int offset;
 final  List<ProductEntityRef> _items;
@override List<ProductEntityRef> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of ModeCatalogEntryPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeCatalogEntryPageCopyWith<_ModeCatalogEntryPage> get copyWith => __$ModeCatalogEntryPageCopyWithImpl<_ModeCatalogEntryPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeCatalogEntryPage&&(identical(other.collection, collection) || other.collection == collection)&&(identical(other.offset, offset) || other.offset == offset)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,collection,offset,const DeepCollectionEquality().hash(_items),nextOffset);
}

@override
String toString() {
    return 'ModeCatalogEntryPage(collection: $collection, offset: $offset, items: $items, nextOffset: $nextOffset)';
}


}

/// @nodoc
abstract mixin class _$ModeCatalogEntryPageCopyWith<$Res> implements $ModeCatalogEntryPageCopyWith<$Res> {
  factory _$ModeCatalogEntryPageCopyWith(_ModeCatalogEntryPage value, $Res Function(_ModeCatalogEntryPage) _then) = __$ModeCatalogEntryPageCopyWithImpl;
@override @useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


@override $ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class __$ModeCatalogEntryPageCopyWithImpl<$Res>
    implements _$ModeCatalogEntryPageCopyWith<$Res> {
  __$ModeCatalogEntryPageCopyWithImpl(this._self, this._then);

  final _ModeCatalogEntryPage _self;
  final $Res Function(_ModeCatalogEntryPage) _then;

/// Create a copy of ModeCatalogEntryPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_ModeCatalogEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of ModeCatalogEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}

/// @nodoc
mixin _$ModeCatalogEntityRead {

 ProductEntityRef get reference; ThreadModeDescriptorRead get value;
/// Create a copy of ModeCatalogEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogEntityReadCopyWith<ModeCatalogEntityRead> get copyWith => _$ModeCatalogEntityReadCopyWithImpl<ModeCatalogEntityRead>(this as ModeCatalogEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeCatalogEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ModeCatalogEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}



}

/// @nodoc
abstract mixin class $ModeCatalogEntityReadCopyWith<$Res>  {
  factory $ModeCatalogEntityReadCopyWith(ModeCatalogEntityRead value, $Res Function(ModeCatalogEntityRead) _then) = _$ModeCatalogEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, ThreadModeDescriptorRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$ThreadModeDescriptorReadCopyWith<$Res> get value;

}
/// @nodoc
class _$ModeCatalogEntityReadCopyWithImpl<$Res>
    implements $ModeCatalogEntityReadCopyWith<$Res> {
  _$ModeCatalogEntityReadCopyWithImpl(this._self, this._then);

  final ModeCatalogEntityRead _self;
  final $Res Function(ModeCatalogEntityRead) _then;

/// Create a copy of ModeCatalogEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(ModeCatalogEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadModeDescriptorRead,
  ));
}
/// Create a copy of ModeCatalogEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ModeCatalogEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadModeDescriptorReadCopyWith<$Res> get value {

  return $ThreadModeDescriptorReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeCatalogEntityRead].
extension ModeCatalogEntityReadPatterns on ModeCatalogEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeCatalogEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeCatalogEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeCatalogEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeCatalogEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  ThreadModeDescriptorRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeCatalogEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  ThreadModeDescriptorRead value)  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogEntityRead():
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  ThreadModeDescriptorRead value)?  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ModeCatalogEntityRead implements ModeCatalogEntityRead {
  const _ModeCatalogEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  ThreadModeDescriptorRead value;

/// Create a copy of ModeCatalogEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeCatalogEntityReadCopyWith<_ModeCatalogEntityRead> get copyWith => __$ModeCatalogEntityReadCopyWithImpl<_ModeCatalogEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeCatalogEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}



}

/// @nodoc
abstract mixin class _$ModeCatalogEntityReadCopyWith<$Res> implements $ModeCatalogEntityReadCopyWith<$Res> {
  factory _$ModeCatalogEntityReadCopyWith(_ModeCatalogEntityRead value, $Res Function(_ModeCatalogEntityRead) _then) = __$ModeCatalogEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, ThreadModeDescriptorRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $ThreadModeDescriptorReadCopyWith<$Res> get value;

}
/// @nodoc
class __$ModeCatalogEntityReadCopyWithImpl<$Res>
    implements _$ModeCatalogEntityReadCopyWith<$Res> {
  __$ModeCatalogEntityReadCopyWithImpl(this._self, this._then);

  final _ModeCatalogEntityRead _self;
  final $Res Function(_ModeCatalogEntityRead) _then;

/// Create a copy of ModeCatalogEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_ModeCatalogEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadModeDescriptorRead,
  ));
}

/// Create a copy of ModeCatalogEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ModeCatalogEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadModeDescriptorReadCopyWith<$Res> get value {

  return $ThreadModeDescriptorReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadModeDescriptorReadPage {

 int get listId; int get offset; int get total; List<ThreadModeDescriptorRead> get items; int? get nextOffset;
/// Create a copy of ThreadModeDescriptorReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadModeDescriptorReadPageCopyWith<ThreadModeDescriptorReadPage> get copyWith => _$ThreadModeDescriptorReadPageCopyWithImpl<ThreadModeDescriptorReadPage>(this as ThreadModeDescriptorReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadModeDescriptorReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadModeDescriptorReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as ThreadModeDescriptorReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $ThreadModeDescriptorReadPageCopyWith<$Res>  {
  factory $ThreadModeDescriptorReadPageCopyWith(ThreadModeDescriptorReadPage value, $Res Function(ThreadModeDescriptorReadPage) _then) = _$ThreadModeDescriptorReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<ThreadModeDescriptorRead> items, int? nextOffset
});




}
/// @nodoc
class _$ThreadModeDescriptorReadPageCopyWithImpl<$Res>
    implements $ThreadModeDescriptorReadPageCopyWith<$Res> {
  _$ThreadModeDescriptorReadPageCopyWithImpl(this._self, this._then);

  final ThreadModeDescriptorReadPage _self;
  final $Res Function(ThreadModeDescriptorReadPage) _then;

/// Create a copy of ThreadModeDescriptorReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(ThreadModeDescriptorReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ThreadModeDescriptorRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadModeDescriptorReadPage].
extension ThreadModeDescriptorReadPagePatterns on ThreadModeDescriptorReadPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadModeDescriptorReadPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadModeDescriptorReadPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadModeDescriptorReadPage value)  $default,){
final _that = this;
switch (_that) {
case _ThreadModeDescriptorReadPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadModeDescriptorReadPage value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadModeDescriptorReadPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<ThreadModeDescriptorRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadModeDescriptorReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<ThreadModeDescriptorRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _ThreadModeDescriptorReadPage():
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int listId,  int offset,  int total,  List<ThreadModeDescriptorRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _ThreadModeDescriptorReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadModeDescriptorReadPage implements ThreadModeDescriptorReadPage {
  const _ThreadModeDescriptorReadPage({required this.listId, required this.offset, required this.total, required  List<ThreadModeDescriptorRead> items, required this.nextOffset}): _items = items;


@override final  int listId;
@override final  int offset;
@override final  int total;
 final  List<ThreadModeDescriptorRead> _items;
@override List<ThreadModeDescriptorRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of ThreadModeDescriptorReadPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadModeDescriptorReadPageCopyWith<_ThreadModeDescriptorReadPage> get copyWith => __$ThreadModeDescriptorReadPageCopyWithImpl<_ThreadModeDescriptorReadPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadModeDescriptorReadPage&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,listId,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}



}

/// @nodoc
abstract mixin class _$ThreadModeDescriptorReadPageCopyWith<$Res> implements $ThreadModeDescriptorReadPageCopyWith<$Res> {
  factory _$ThreadModeDescriptorReadPageCopyWith(_ThreadModeDescriptorReadPage value, $Res Function(_ThreadModeDescriptorReadPage) _then) = __$ThreadModeDescriptorReadPageCopyWithImpl;
@override @useResult
$Res call({
 int listId, int offset, int total, List<ThreadModeDescriptorRead> items, int? nextOffset
});




}
/// @nodoc
class __$ThreadModeDescriptorReadPageCopyWithImpl<$Res>
    implements _$ThreadModeDescriptorReadPageCopyWith<$Res> {
  __$ThreadModeDescriptorReadPageCopyWithImpl(this._self, this._then);

  final _ThreadModeDescriptorReadPage _self;
  final $Res Function(_ThreadModeDescriptorReadPage) _then;

/// Create a copy of ThreadModeDescriptorReadPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_ThreadModeDescriptorReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<ThreadModeDescriptorRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
