// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mode_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadModeId {





@override
bool operator ==(Object other) {
  final _this = this as ThreadModeId;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadModeId&&(identical(other.id, _this.id) || other.id == _this.id));
}


@override
int get hashCode {
  final _this = this as ThreadModeId;
  return Object.hash(runtimeType,_this.id);
}

@override
String toString() {
  final _this = this as ThreadModeId;
  return 'ThreadModeId(id: ${_this.id})';
}


}




/// Adds pattern-matching-related methods to [ThreadModeId].
extension ThreadModeIdPatterns on ThreadModeId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$ThreadModeDescriptor {

 ThreadModeId get id; String get displayName; String get description; int get order; bool get hasWorkflow; bool get readOnly;
/// Create a copy of ThreadModeDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadModeDescriptorCopyWith<ThreadModeDescriptor> get copyWith => _$ThreadModeDescriptorCopyWithImpl<ThreadModeDescriptor>(this as ThreadModeDescriptor, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadModeDescriptor;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadModeDescriptor&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.order, _this.order) || other.order == _this.order)&&(identical(other.hasWorkflow, _this.hasWorkflow) || other.hasWorkflow == _this.hasWorkflow)&&(identical(other.readOnly, _this.readOnly) || other.readOnly == _this.readOnly));
}


@override
int get hashCode {
  final _this = this as ThreadModeDescriptor;
  return Object.hash(runtimeType,_this.id,_this.displayName,_this.description,_this.order,_this.hasWorkflow,_this.readOnly);
}

@override
String toString() {
  final _this = this as ThreadModeDescriptor;
  return 'ThreadModeDescriptor(id: ${_this.id}, displayName: ${_this.displayName}, description: ${_this.description}, order: ${_this.order}, hasWorkflow: ${_this.hasWorkflow}, readOnly: ${_this.readOnly})';
}


}

/// @nodoc
abstract mixin class $ThreadModeDescriptorCopyWith<$Res>  {
  factory $ThreadModeDescriptorCopyWith(ThreadModeDescriptor value, $Res Function(ThreadModeDescriptor) _then) = _$ThreadModeDescriptorCopyWithImpl;
@useResult
$Res call({
 ThreadModeId id, String displayName, String description, int order, bool hasWorkflow, bool readOnly
});




}
/// @nodoc
class _$ThreadModeDescriptorCopyWithImpl<$Res>
    implements $ThreadModeDescriptorCopyWith<$Res> {
  _$ThreadModeDescriptorCopyWithImpl(this._self, this._then);

  final ThreadModeDescriptor _self;
  final $Res Function(ThreadModeDescriptor) _then;

/// Create a copy of ThreadModeDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? description = null,Object? order = null,Object? hasWorkflow = null,Object? readOnly = null,}) {
  return _then(ThreadModeDescriptor(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ThreadModeId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,hasWorkflow: null == hasWorkflow ? _self.hasWorkflow : hasWorkflow // ignore: cast_nullable_to_non_nullable
as bool,readOnly: null == readOnly ? _self.readOnly : readOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadModeDescriptor].
extension ThreadModeDescriptorPatterns on ThreadModeDescriptor {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadModeDescriptor value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadModeDescriptor() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadModeDescriptor value)  $default,){
final _that = this;
switch (_that) {
case _ThreadModeDescriptor():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadModeDescriptor value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadModeDescriptor() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadModeId id,  String displayName,  String description,  int order,  bool hasWorkflow,  bool readOnly)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadModeDescriptor() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadModeId id,  String displayName,  String description,  int order,  bool hasWorkflow,  bool readOnly)  $default,) {final _that = this;
switch (_that) {
case _ThreadModeDescriptor():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadModeId id,  String displayName,  String description,  int order,  bool hasWorkflow,  bool readOnly)?  $default,) {final _that = this;
switch (_that) {
case _ThreadModeDescriptor() when $default != null:
return $default(_that.id,_that.displayName,_that.description,_that.order,_that.hasWorkflow,_that.readOnly);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadModeDescriptor implements ThreadModeDescriptor {
  const _ThreadModeDescriptor({required this.id, required this.displayName, required this.description, required this.order, required this.hasWorkflow, required this.readOnly});


@override final  ThreadModeId id;
@override final  String displayName;
@override final  String description;
@override final  int order;
@override final  bool hasWorkflow;
@override final  bool readOnly;

/// Create a copy of ThreadModeDescriptor
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadModeDescriptorCopyWith<_ThreadModeDescriptor> get copyWith => __$ThreadModeDescriptorCopyWithImpl<_ThreadModeDescriptor>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadModeDescriptor&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.order, order) || other.order == order)&&(identical(other.hasWorkflow, hasWorkflow) || other.hasWorkflow == hasWorkflow)&&(identical(other.readOnly, readOnly) || other.readOnly == readOnly));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName,description,order,hasWorkflow,readOnly);
}

@override
String toString() {
    return 'ThreadModeDescriptor(id: $id, displayName: $displayName, description: $description, order: $order, hasWorkflow: $hasWorkflow, readOnly: $readOnly)';
}


}

/// @nodoc
abstract mixin class _$ThreadModeDescriptorCopyWith<$Res> implements $ThreadModeDescriptorCopyWith<$Res> {
  factory _$ThreadModeDescriptorCopyWith(_ThreadModeDescriptor value, $Res Function(_ThreadModeDescriptor) _then) = __$ThreadModeDescriptorCopyWithImpl;
@override @useResult
$Res call({
 ThreadModeId id, String displayName, String description, int order, bool hasWorkflow, bool readOnly
});




}
/// @nodoc
class __$ThreadModeDescriptorCopyWithImpl<$Res>
    implements _$ThreadModeDescriptorCopyWith<$Res> {
  __$ThreadModeDescriptorCopyWithImpl(this._self, this._then);

  final _ThreadModeDescriptor _self;
  final $Res Function(_ThreadModeDescriptor) _then;

/// Create a copy of ThreadModeDescriptor
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? description = null,Object? order = null,Object? hasWorkflow = null,Object? readOnly = null,}) {
  return _then(_ThreadModeDescriptor(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ThreadModeId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,hasWorkflow: null == hasWorkflow ? _self.hasWorkflow : hasWorkflow // ignore: cast_nullable_to_non_nullable
as bool,readOnly: null == readOnly ? _self.readOnly : readOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$ModesValue {

 int get revision; List<ThreadModeDescriptor> get modes;
/// Create a copy of ModesValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModesValueCopyWith<ModesValue> get copyWith => _$ModesValueCopyWithImpl<ModesValue>(this as ModesValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModesValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModesValue&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&const DeepCollectionEquality().equals(other.modes, _this.modes));
}


@override
int get hashCode {
  final _this = this as ModesValue;
  return Object.hash(runtimeType,_this.revision,const DeepCollectionEquality().hash(_this.modes));
}

@override
String toString() {
  final _this = this as ModesValue;
  return 'ModesValue(revision: ${_this.revision}, modes: ${_this.modes})';
}


}

/// @nodoc
abstract mixin class $ModesValueCopyWith<$Res>  {
  factory $ModesValueCopyWith(ModesValue value, $Res Function(ModesValue) _then) = _$ModesValueCopyWithImpl;
@useResult
$Res call({
 int revision, List<ThreadModeDescriptor> modes
});




}
/// @nodoc
class _$ModesValueCopyWithImpl<$Res>
    implements $ModesValueCopyWith<$Res> {
  _$ModesValueCopyWithImpl(this._self, this._then);

  final ModesValue _self;
  final $Res Function(ModesValue) _then;

/// Create a copy of ModesValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? modes = null,}) {
  return _then(ModesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,modes: null == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as List<ThreadModeDescriptor>,
  ));
}

}


/// Adds pattern-matching-related methods to [ModesValue].
extension ModesValuePatterns on ModesValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModesValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModesValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModesValue value)  $default,){
final _that = this;
switch (_that) {
case _ModesValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModesValue value)?  $default,){
final _that = this;
switch (_that) {
case _ModesValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  List<ThreadModeDescriptor> modes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModesValue() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  List<ThreadModeDescriptor> modes)  $default,) {final _that = this;
switch (_that) {
case _ModesValue():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  List<ThreadModeDescriptor> modes)?  $default,) {final _that = this;
switch (_that) {
case _ModesValue() when $default != null:
return $default(_that.revision,_that.modes);case _:
  return null;

}
}

}

/// @nodoc


class _ModesValue implements ModesValue {
  const _ModesValue({required this.revision, required  List<ThreadModeDescriptor> modes}): _modes = modes;


@override final  int revision;
 final  List<ThreadModeDescriptor> _modes;
@override List<ThreadModeDescriptor> get modes {
  if (_modes is EqualUnmodifiableListView) return _modes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_modes);
}


/// Create a copy of ModesValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModesValueCopyWith<_ModesValue> get copyWith => __$ModesValueCopyWithImpl<_ModesValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModesValue&&(identical(other.revision, revision) || other.revision == revision)&&const DeepCollectionEquality().equals(other.modes, _modes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,const DeepCollectionEquality().hash(_modes));
}

@override
String toString() {
    return 'ModesValue(revision: $revision, modes: $modes)';
}


}

/// @nodoc
abstract mixin class _$ModesValueCopyWith<$Res> implements $ModesValueCopyWith<$Res> {
  factory _$ModesValueCopyWith(_ModesValue value, $Res Function(_ModesValue) _then) = __$ModesValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, List<ThreadModeDescriptor> modes
});




}
/// @nodoc
class __$ModesValueCopyWithImpl<$Res>
    implements _$ModesValueCopyWith<$Res> {
  __$ModesValueCopyWithImpl(this._self, this._then);

  final _ModesValue _self;
  final $Res Function(_ModesValue) _then;

/// Create a copy of ModesValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? modes = null,}) {
  return _then(_ModesValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,modes: null == modes ? _self._modes : modes // ignore: cast_nullable_to_non_nullable
as List<ThreadModeDescriptor>,
  ));
}


}

// dart format on
