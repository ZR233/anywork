// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_entries.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AcpAccountDirectory {

 ProductReadOrigin get origin; ConfigurationReadRef get reference; int get revision; int get updatedAt; List<AcpAccountSettings> get accounts;
/// Create a copy of AcpAccountDirectory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountDirectoryCopyWith<AcpAccountDirectory> get copyWith => _$AcpAccountDirectoryCopyWithImpl<AcpAccountDirectory>(this as AcpAccountDirectory, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAccountDirectory;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountDirectory&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&const DeepCollectionEquality().equals(other.accounts, _this.accounts));
}


@override
int get hashCode {
  final _this = this as AcpAccountDirectory;
  return Object.hash(runtimeType,_this.origin,_this.reference,_this.revision,_this.updatedAt,const DeepCollectionEquality().hash(_this.accounts));
}



}

/// @nodoc
abstract mixin class $AcpAccountDirectoryCopyWith<$Res>  {
  factory $AcpAccountDirectoryCopyWith(AcpAccountDirectory value, $Res Function(AcpAccountDirectory) _then) = _$AcpAccountDirectoryCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, ConfigurationReadRef reference, int revision, int updatedAt, List<AcpAccountSettings> accounts
});


$ProductReadOriginCopyWith<$Res> get origin;$ConfigurationReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$AcpAccountDirectoryCopyWithImpl<$Res>
    implements $AcpAccountDirectoryCopyWith<$Res> {
  _$AcpAccountDirectoryCopyWithImpl(this._self, this._then);

  final AcpAccountDirectory _self;
  final $Res Function(AcpAccountDirectory) _then;

/// Create a copy of AcpAccountDirectory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,Object? revision = null,Object? updatedAt = null,Object? accounts = null,}) {
  return _then(AcpAccountDirectory(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ConfigurationReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<AcpAccountSettings>,
  ));
}
/// Create a copy of AcpAccountDirectory
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of AcpAccountDirectory
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadRefCopyWith<$Res> get reference {

  return $ConfigurationReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAccountDirectory].
extension AcpAccountDirectoryPatterns on AcpAccountDirectory {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAccountDirectory value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAccountDirectory() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAccountDirectory value)  $default,){
final _that = this;
switch (_that) {
case _AcpAccountDirectory():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAccountDirectory value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAccountDirectory() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ConfigurationReadRef reference,  int revision,  int updatedAt,  List<AcpAccountSettings> accounts)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAccountDirectory() when $default != null:
return $default(_that.origin,_that.reference,_that.revision,_that.updatedAt,_that.accounts);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ConfigurationReadRef reference,  int revision,  int updatedAt,  List<AcpAccountSettings> accounts)  $default,) {final _that = this;
switch (_that) {
case _AcpAccountDirectory():
return $default(_that.origin,_that.reference,_that.revision,_that.updatedAt,_that.accounts);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  ConfigurationReadRef reference,  int revision,  int updatedAt,  List<AcpAccountSettings> accounts)?  $default,) {final _that = this;
switch (_that) {
case _AcpAccountDirectory() when $default != null:
return $default(_that.origin,_that.reference,_that.revision,_that.updatedAt,_that.accounts);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAccountDirectory extends AcpAccountDirectory {
  const _AcpAccountDirectory({required this.origin, required this.reference, required this.revision, required this.updatedAt, required  List<AcpAccountSettings> accounts}): _accounts = accounts,super._();


@override final  ProductReadOrigin origin;
@override final  ConfigurationReadRef reference;
@override final  int revision;
@override final  int updatedAt;
 final  List<AcpAccountSettings> _accounts;
@override List<AcpAccountSettings> get accounts {
  if (_accounts is EqualUnmodifiableListView) return _accounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_accounts);
}


/// Create a copy of AcpAccountDirectory
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAccountDirectoryCopyWith<_AcpAccountDirectory> get copyWith => __$AcpAccountDirectoryCopyWithImpl<_AcpAccountDirectory>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAccountDirectory&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other.accounts, _accounts));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference,revision,updatedAt,const DeepCollectionEquality().hash(_accounts));
}



}

/// @nodoc
abstract mixin class _$AcpAccountDirectoryCopyWith<$Res> implements $AcpAccountDirectoryCopyWith<$Res> {
  factory _$AcpAccountDirectoryCopyWith(_AcpAccountDirectory value, $Res Function(_AcpAccountDirectory) _then) = __$AcpAccountDirectoryCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, ConfigurationReadRef reference, int revision, int updatedAt, List<AcpAccountSettings> accounts
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $ConfigurationReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$AcpAccountDirectoryCopyWithImpl<$Res>
    implements _$AcpAccountDirectoryCopyWith<$Res> {
  __$AcpAccountDirectoryCopyWithImpl(this._self, this._then);

  final _AcpAccountDirectory _self;
  final $Res Function(_AcpAccountDirectory) _then;

/// Create a copy of AcpAccountDirectory
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,Object? revision = null,Object? updatedAt = null,Object? accounts = null,}) {
  return _then(_AcpAccountDirectory(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ConfigurationReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,accounts: null == accounts ? _self._accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<AcpAccountSettings>,
  ));
}

/// Create a copy of AcpAccountDirectory
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of AcpAccountDirectory
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadRefCopyWith<$Res> get reference {

  return $ConfigurationReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$AccountTemplateChoice {

 Object get template;



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplateChoice;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplateChoice&&const DeepCollectionEquality().equals(other.template, _this.template));
}


@override
int get hashCode {
  final _this = this as AccountTemplateChoice;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.template));
}



}

/// @nodoc
class $AccountTemplateChoiceCopyWith<$Res>  {
$AccountTemplateChoiceCopyWith(AccountTemplateChoice _, $Res Function(AccountTemplateChoice) __);
}


/// Adds pattern-matching-related methods to [AccountTemplateChoice].
extension AccountTemplateChoicePatterns on AccountTemplateChoice {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NativeAccountTemplateChoice value)?  native,TResult Function( AcpAccountTemplateChoice value)?  acp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NativeAccountTemplateChoice() when native != null:
return native(_that);case AcpAccountTemplateChoice() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NativeAccountTemplateChoice value)  native,required TResult Function( AcpAccountTemplateChoice value)  acp,}){
final _that = this;
switch (_that) {
case NativeAccountTemplateChoice():
return native(_that);case AcpAccountTemplateChoice():
return acp(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NativeAccountTemplateChoice value)?  native,TResult? Function( AcpAccountTemplateChoice value)?  acp,}){
final _that = this;
switch (_that) {
case NativeAccountTemplateChoice() when native != null:
return native(_that);case AcpAccountTemplateChoice() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( AccountTemplate template)?  native,TResult Function( AcpAccountTemplate template)?  acp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NativeAccountTemplateChoice() when native != null:
return native(_that.template);case AcpAccountTemplateChoice() when acp != null:
return acp(_that.template);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( AccountTemplate template)  native,required TResult Function( AcpAccountTemplate template)  acp,}) {final _that = this;
switch (_that) {
case NativeAccountTemplateChoice():
return native(_that.template);case AcpAccountTemplateChoice():
return acp(_that.template);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( AccountTemplate template)?  native,TResult? Function( AcpAccountTemplate template)?  acp,}) {final _that = this;
switch (_that) {
case NativeAccountTemplateChoice() when native != null:
return native(_that.template);case AcpAccountTemplateChoice() when acp != null:
return acp(_that.template);case _:
  return null;

}
}

}

/// @nodoc


class NativeAccountTemplateChoice extends AccountTemplateChoice {
  const NativeAccountTemplateChoice(this.template): super._();


@override final  AccountTemplate template;

/// Create a copy of AccountTemplateChoice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NativeAccountTemplateChoiceCopyWith<NativeAccountTemplateChoice> get copyWith => _$NativeAccountTemplateChoiceCopyWithImpl<NativeAccountTemplateChoice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeAccountTemplateChoice&&(identical(other.template, template) || other.template == template));
}


@override
int get hashCode {
    return Object.hash(runtimeType,template);
}



}

/// @nodoc
abstract mixin class $NativeAccountTemplateChoiceCopyWith<$Res> implements $AccountTemplateChoiceCopyWith<$Res> {
  factory $NativeAccountTemplateChoiceCopyWith(NativeAccountTemplateChoice value, $Res Function(NativeAccountTemplateChoice) _then) = _$NativeAccountTemplateChoiceCopyWithImpl;
@useResult
$Res call({
 AccountTemplate template
});


$AccountTemplateCopyWith<$Res> get template;

}
/// @nodoc
class _$NativeAccountTemplateChoiceCopyWithImpl<$Res>
    implements $NativeAccountTemplateChoiceCopyWith<$Res> {
  _$NativeAccountTemplateChoiceCopyWithImpl(this._self, this._then);

  final NativeAccountTemplateChoice _self;
  final $Res Function(NativeAccountTemplateChoice) _then;

/// Create a copy of AccountTemplateChoice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? template = null,}) {
  return _then(NativeAccountTemplateChoice(
null == template ? _self.template : template // ignore: cast_nullable_to_non_nullable
as AccountTemplate,
  ));
}

/// Create a copy of AccountTemplateChoice
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplateCopyWith<$Res> get template {

  return $AccountTemplateCopyWith<$Res>(_self.template, (value) {
    return _then(_self.copyWith(template: value));
  });
}
}

/// @nodoc


class AcpAccountTemplateChoice extends AccountTemplateChoice {
  const AcpAccountTemplateChoice(this.template): super._();


@override final  AcpAccountTemplate template;

/// Create a copy of AccountTemplateChoice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountTemplateChoiceCopyWith<AcpAccountTemplateChoice> get copyWith => _$AcpAccountTemplateChoiceCopyWithImpl<AcpAccountTemplateChoice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountTemplateChoice&&(identical(other.template, template) || other.template == template));
}


@override
int get hashCode {
    return Object.hash(runtimeType,template);
}



}

/// @nodoc
abstract mixin class $AcpAccountTemplateChoiceCopyWith<$Res> implements $AccountTemplateChoiceCopyWith<$Res> {
  factory $AcpAccountTemplateChoiceCopyWith(AcpAccountTemplateChoice value, $Res Function(AcpAccountTemplateChoice) _then) = _$AcpAccountTemplateChoiceCopyWithImpl;
@useResult
$Res call({
 AcpAccountTemplate template
});


$AcpAccountTemplateCopyWith<$Res> get template;

}
/// @nodoc
class _$AcpAccountTemplateChoiceCopyWithImpl<$Res>
    implements $AcpAccountTemplateChoiceCopyWith<$Res> {
  _$AcpAccountTemplateChoiceCopyWithImpl(this._self, this._then);

  final AcpAccountTemplateChoice _self;
  final $Res Function(AcpAccountTemplateChoice) _then;

/// Create a copy of AccountTemplateChoice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? template = null,}) {
  return _then(AcpAccountTemplateChoice(
null == template ? _self.template : template // ignore: cast_nullable_to_non_nullable
as AcpAccountTemplate,
  ));
}

/// Create a copy of AccountTemplateChoice
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountTemplateCopyWith<$Res> get template {

  return $AcpAccountTemplateCopyWith<$Res>(_self.template, (value) {
    return _then(_self.copyWith(template: value));
  });
}
}

/// @nodoc
mixin _$AccountEntryView {

 Object get account;



@override
bool operator ==(Object other) {
  final _this = this as AccountEntryView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountEntryView&&const DeepCollectionEquality().equals(other.account, _this.account));
}


@override
int get hashCode {
  final _this = this as AccountEntryView;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.account));
}



}

/// @nodoc
class $AccountEntryViewCopyWith<$Res>  {
$AccountEntryViewCopyWith(AccountEntryView _, $Res Function(AccountEntryView) __);
}


/// Adds pattern-matching-related methods to [AccountEntryView].
extension AccountEntryViewPatterns on AccountEntryView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NativeAccountEntryView value)?  native,TResult Function( AcpAccountEntryView value)?  acp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NativeAccountEntryView() when native != null:
return native(_that);case AcpAccountEntryView() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NativeAccountEntryView value)  native,required TResult Function( AcpAccountEntryView value)  acp,}){
final _that = this;
switch (_that) {
case NativeAccountEntryView():
return native(_that);case AcpAccountEntryView():
return acp(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NativeAccountEntryView value)?  native,TResult? Function( AcpAccountEntryView value)?  acp,}){
final _that = this;
switch (_that) {
case NativeAccountEntryView() when native != null:
return native(_that);case AcpAccountEntryView() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( AccountConfiguration account)?  native,TResult Function( AcpAccountSettings account,  AcpAuthState auth,  AcpAccountTemplate? template)?  acp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NativeAccountEntryView() when native != null:
return native(_that.account);case AcpAccountEntryView() when acp != null:
return acp(_that.account,_that.auth,_that.template);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( AccountConfiguration account)  native,required TResult Function( AcpAccountSettings account,  AcpAuthState auth,  AcpAccountTemplate? template)  acp,}) {final _that = this;
switch (_that) {
case NativeAccountEntryView():
return native(_that.account);case AcpAccountEntryView():
return acp(_that.account,_that.auth,_that.template);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( AccountConfiguration account)?  native,TResult? Function( AcpAccountSettings account,  AcpAuthState auth,  AcpAccountTemplate? template)?  acp,}) {final _that = this;
switch (_that) {
case NativeAccountEntryView() when native != null:
return native(_that.account);case AcpAccountEntryView() when acp != null:
return acp(_that.account,_that.auth,_that.template);case _:
  return null;

}
}

}

/// @nodoc


class NativeAccountEntryView extends AccountEntryView {
  const NativeAccountEntryView(this.account): super._();


@override final  AccountConfiguration account;

/// Create a copy of AccountEntryView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NativeAccountEntryViewCopyWith<NativeAccountEntryView> get copyWith => _$NativeAccountEntryViewCopyWithImpl<NativeAccountEntryView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeAccountEntryView&&(identical(other.account, account) || other.account == account));
}


@override
int get hashCode {
    return Object.hash(runtimeType,account);
}



}

/// @nodoc
abstract mixin class $NativeAccountEntryViewCopyWith<$Res> implements $AccountEntryViewCopyWith<$Res> {
  factory $NativeAccountEntryViewCopyWith(NativeAccountEntryView value, $Res Function(NativeAccountEntryView) _then) = _$NativeAccountEntryViewCopyWithImpl;
@useResult
$Res call({
 AccountConfiguration account
});


$AccountConfigurationCopyWith<$Res> get account;

}
/// @nodoc
class _$NativeAccountEntryViewCopyWithImpl<$Res>
    implements $NativeAccountEntryViewCopyWith<$Res> {
  _$NativeAccountEntryViewCopyWithImpl(this._self, this._then);

  final NativeAccountEntryView _self;
  final $Res Function(NativeAccountEntryView) _then;

/// Create a copy of AccountEntryView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? account = null,}) {
  return _then(NativeAccountEntryView(
null == account ? _self.account : account // ignore: cast_nullable_to_non_nullable
as AccountConfiguration,
  ));
}

/// Create a copy of AccountEntryView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountConfigurationCopyWith<$Res> get account {

  return $AccountConfigurationCopyWith<$Res>(_self.account, (value) {
    return _then(_self.copyWith(account: value));
  });
}
}

/// @nodoc


class AcpAccountEntryView extends AccountEntryView {
  const AcpAccountEntryView({required this.account, required this.auth, required this.template}): super._();


@override final  AcpAccountSettings account;
/// 该接入的认证观察状态；没有匹配条目时为未检查，绝不推断为成功。
 final  AcpAuthState auth;
/// 目录里仍可解析的模板；目录未加载时为 null，展示层据此省略品牌与安装说明。
 final  AcpAccountTemplate? template;

/// Create a copy of AccountEntryView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountEntryViewCopyWith<AcpAccountEntryView> get copyWith => _$AcpAccountEntryViewCopyWithImpl<AcpAccountEntryView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountEntryView&&(identical(other.account, account) || other.account == account)&&(identical(other.auth, auth) || other.auth == auth)&&(identical(other.template, template) || other.template == template));
}


@override
int get hashCode {
    return Object.hash(runtimeType,account,auth,template);
}



}

/// @nodoc
abstract mixin class $AcpAccountEntryViewCopyWith<$Res> implements $AccountEntryViewCopyWith<$Res> {
  factory $AcpAccountEntryViewCopyWith(AcpAccountEntryView value, $Res Function(AcpAccountEntryView) _then) = _$AcpAccountEntryViewCopyWithImpl;
@useResult
$Res call({
 AcpAccountSettings account, AcpAuthState auth, AcpAccountTemplate? template
});


$AcpAccountSettingsCopyWith<$Res> get account;$AcpAuthStateCopyWith<$Res> get auth;$AcpAccountTemplateCopyWith<$Res>? get template;

}
/// @nodoc
class _$AcpAccountEntryViewCopyWithImpl<$Res>
    implements $AcpAccountEntryViewCopyWith<$Res> {
  _$AcpAccountEntryViewCopyWithImpl(this._self, this._then);

  final AcpAccountEntryView _self;
  final $Res Function(AcpAccountEntryView) _then;

/// Create a copy of AccountEntryView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? account = null,Object? auth = null,Object? template = freezed,}) {
  return _then(AcpAccountEntryView(
account: null == account ? _self.account : account // ignore: cast_nullable_to_non_nullable
as AcpAccountSettings,auth: null == auth ? _self.auth : auth // ignore: cast_nullable_to_non_nullable
as AcpAuthState,template: freezed == template ? _self.template : template // ignore: cast_nullable_to_non_nullable
as AcpAccountTemplate?,
  ));
}

/// Create a copy of AccountEntryView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountSettingsCopyWith<$Res> get account {

  return $AcpAccountSettingsCopyWith<$Res>(_self.account, (value) {
    return _then(_self.copyWith(account: value));
  });
}/// Create a copy of AccountEntryView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthStateCopyWith<$Res> get auth {

  return $AcpAuthStateCopyWith<$Res>(_self.auth, (value) {
    return _then(_self.copyWith(auth: value));
  });
}/// Create a copy of AccountEntryView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountTemplateCopyWith<$Res>? get template {
    if (_self.template == null) {
    return null;
  }

  return $AcpAccountTemplateCopyWith<$Res>(_self.template!, (value) {
    return _then(_self.copyWith(template: value));
  });
}
}

/// @nodoc
mixin _$AccountDirectoryView {

 List<AccountEntryView> get entries; List<AccountTemplateChoice> get templates;/// 该投影套用的 `acpAuth` 水位；0 表示没有可用的认证观察。
 int get authRevision;
/// Create a copy of AccountDirectoryView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountDirectoryViewCopyWith<AccountDirectoryView> get copyWith => _$AccountDirectoryViewCopyWithImpl<AccountDirectoryView>(this as AccountDirectoryView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountDirectoryView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountDirectoryView&&const DeepCollectionEquality().equals(other.entries, _this.entries)&&const DeepCollectionEquality().equals(other.templates, _this.templates)&&(identical(other.authRevision, _this.authRevision) || other.authRevision == _this.authRevision));
}


@override
int get hashCode {
  final _this = this as AccountDirectoryView;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.entries),const DeepCollectionEquality().hash(_this.templates),_this.authRevision);
}



}

/// @nodoc
abstract mixin class $AccountDirectoryViewCopyWith<$Res>  {
  factory $AccountDirectoryViewCopyWith(AccountDirectoryView value, $Res Function(AccountDirectoryView) _then) = _$AccountDirectoryViewCopyWithImpl;
@useResult
$Res call({
 List<AccountEntryView> entries, List<AccountTemplateChoice> templates, int authRevision
});




}
/// @nodoc
class _$AccountDirectoryViewCopyWithImpl<$Res>
    implements $AccountDirectoryViewCopyWith<$Res> {
  _$AccountDirectoryViewCopyWithImpl(this._self, this._then);

  final AccountDirectoryView _self;
  final $Res Function(AccountDirectoryView) _then;

/// Create a copy of AccountDirectoryView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entries = null,Object? templates = null,Object? authRevision = null,}) {
  return _then(AccountDirectoryView(
entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<AccountEntryView>,templates: null == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as List<AccountTemplateChoice>,authRevision: null == authRevision ? _self.authRevision : authRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountDirectoryView].
extension AccountDirectoryViewPatterns on AccountDirectoryView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountDirectoryView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountDirectoryView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountDirectoryView value)  $default,){
final _that = this;
switch (_that) {
case _AccountDirectoryView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountDirectoryView value)?  $default,){
final _that = this;
switch (_that) {
case _AccountDirectoryView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<AccountEntryView> entries,  List<AccountTemplateChoice> templates,  int authRevision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountDirectoryView() when $default != null:
return $default(_that.entries,_that.templates,_that.authRevision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<AccountEntryView> entries,  List<AccountTemplateChoice> templates,  int authRevision)  $default,) {final _that = this;
switch (_that) {
case _AccountDirectoryView():
return $default(_that.entries,_that.templates,_that.authRevision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<AccountEntryView> entries,  List<AccountTemplateChoice> templates,  int authRevision)?  $default,) {final _that = this;
switch (_that) {
case _AccountDirectoryView() when $default != null:
return $default(_that.entries,_that.templates,_that.authRevision);case _:
  return null;

}
}

}

/// @nodoc


class _AccountDirectoryView extends AccountDirectoryView {
  const _AccountDirectoryView({required  List<AccountEntryView> entries, required  List<AccountTemplateChoice> templates, required this.authRevision}): _entries = entries,_templates = templates,super._();


 final  List<AccountEntryView> _entries;
@override List<AccountEntryView> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}

 final  List<AccountTemplateChoice> _templates;
@override List<AccountTemplateChoice> get templates {
  if (_templates is EqualUnmodifiableListView) return _templates;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_templates);
}

/// 该投影套用的 `acpAuth` 水位；0 表示没有可用的认证观察。
@override final  int authRevision;

/// Create a copy of AccountDirectoryView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountDirectoryViewCopyWith<_AccountDirectoryView> get copyWith => __$AccountDirectoryViewCopyWithImpl<_AccountDirectoryView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountDirectoryView&&const DeepCollectionEquality().equals(other.entries, _entries)&&const DeepCollectionEquality().equals(other.templates, _templates)&&(identical(other.authRevision, authRevision) || other.authRevision == authRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_entries),const DeepCollectionEquality().hash(_templates),authRevision);
}



}

/// @nodoc
abstract mixin class _$AccountDirectoryViewCopyWith<$Res> implements $AccountDirectoryViewCopyWith<$Res> {
  factory _$AccountDirectoryViewCopyWith(_AccountDirectoryView value, $Res Function(_AccountDirectoryView) _then) = __$AccountDirectoryViewCopyWithImpl;
@override @useResult
$Res call({
 List<AccountEntryView> entries, List<AccountTemplateChoice> templates, int authRevision
});




}
/// @nodoc
class __$AccountDirectoryViewCopyWithImpl<$Res>
    implements _$AccountDirectoryViewCopyWith<$Res> {
  __$AccountDirectoryViewCopyWithImpl(this._self, this._then);

  final _AccountDirectoryView _self;
  final $Res Function(_AccountDirectoryView) _then;

/// Create a copy of AccountDirectoryView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entries = null,Object? templates = null,Object? authRevision = null,}) {
  return _then(_AccountDirectoryView(
entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<AccountEntryView>,templates: null == templates ? _self._templates : templates // ignore: cast_nullable_to_non_nullable
as List<AccountTemplateChoice>,authRevision: null == authRevision ? _self.authRevision : authRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
