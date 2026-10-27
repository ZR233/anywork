// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAccountDetail {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as BridgeAccountDetail;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountDetail&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as BridgeAccountDetail;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as BridgeAccountDetail;
  return 'BridgeAccountDetail(field0: ${_this.field0})';
}


}

/// @nodoc
class $BridgeAccountDetailCopyWith<$Res>  {
$BridgeAccountDetailCopyWith(BridgeAccountDetail _, $Res Function(BridgeAccountDetail) __);
}


/// Adds pattern-matching-related methods to [BridgeAccountDetail].
extension BridgeAccountDetailPatterns on BridgeAccountDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountDetail_Native value)?  native,TResult Function( BridgeAccountDetail_Acp value)?  acp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountDetail_Native() when native != null:
return native(_that);case BridgeAccountDetail_Acp() when acp != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountDetail_Native value)  native,required TResult Function( BridgeAccountDetail_Acp value)  acp,}){
final _that = this;
switch (_that) {
case BridgeAccountDetail_Native():
return native(_that);case BridgeAccountDetail_Acp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountDetail_Native value)?  native,TResult? Function( BridgeAccountDetail_Acp value)?  acp,}){
final _that = this;
switch (_that) {
case BridgeAccountDetail_Native() when native != null:
return native(_that);case BridgeAccountDetail_Acp() when acp != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAccountSettingsDto field0)?  native,TResult Function( BridgeAcpAccountSettings field0)?  acp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountDetail_Native() when native != null:
return native(_that.field0);case BridgeAccountDetail_Acp() when acp != null:
return acp(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAccountSettingsDto field0)  native,required TResult Function( BridgeAcpAccountSettings field0)  acp,}) {final _that = this;
switch (_that) {
case BridgeAccountDetail_Native():
return native(_that.field0);case BridgeAccountDetail_Acp():
return acp(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAccountSettingsDto field0)?  native,TResult? Function( BridgeAcpAccountSettings field0)?  acp,}) {final _that = this;
switch (_that) {
case BridgeAccountDetail_Native() when native != null:
return native(_that.field0);case BridgeAccountDetail_Acp() when acp != null:
return acp(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountDetail_Native extends BridgeAccountDetail {
  const BridgeAccountDetail_Native(this.field0): super._();


@override final  BridgeAccountSettingsDto field0;

/// Create a copy of BridgeAccountDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountDetail_NativeCopyWith<BridgeAccountDetail_Native> get copyWith => _$BridgeAccountDetail_NativeCopyWithImpl<BridgeAccountDetail_Native>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountDetail_Native&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeAccountDetail.native(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountDetail_NativeCopyWith<$Res> implements $BridgeAccountDetailCopyWith<$Res> {
  factory $BridgeAccountDetail_NativeCopyWith(BridgeAccountDetail_Native value, $Res Function(BridgeAccountDetail_Native) _then) = _$BridgeAccountDetail_NativeCopyWithImpl;
@useResult
$Res call({
 BridgeAccountSettingsDto field0
});




}
/// @nodoc
class _$BridgeAccountDetail_NativeCopyWithImpl<$Res>
    implements $BridgeAccountDetail_NativeCopyWith<$Res> {
  _$BridgeAccountDetail_NativeCopyWithImpl(this._self, this._then);

  final BridgeAccountDetail_Native _self;
  final $Res Function(BridgeAccountDetail_Native) _then;

/// Create a copy of BridgeAccountDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeAccountDetail_Native(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeAccountSettingsDto,
  ));
}


}

/// @nodoc


class BridgeAccountDetail_Acp extends BridgeAccountDetail {
  const BridgeAccountDetail_Acp(this.field0): super._();


@override final  BridgeAcpAccountSettings field0;

/// Create a copy of BridgeAccountDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountDetail_AcpCopyWith<BridgeAccountDetail_Acp> get copyWith => _$BridgeAccountDetail_AcpCopyWithImpl<BridgeAccountDetail_Acp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountDetail_Acp&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeAccountDetail.acp(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountDetail_AcpCopyWith<$Res> implements $BridgeAccountDetailCopyWith<$Res> {
  factory $BridgeAccountDetail_AcpCopyWith(BridgeAccountDetail_Acp value, $Res Function(BridgeAccountDetail_Acp) _then) = _$BridgeAccountDetail_AcpCopyWithImpl;
@useResult
$Res call({
 BridgeAcpAccountSettings field0
});




}
/// @nodoc
class _$BridgeAccountDetail_AcpCopyWithImpl<$Res>
    implements $BridgeAccountDetail_AcpCopyWith<$Res> {
  _$BridgeAccountDetail_AcpCopyWithImpl(this._self, this._then);

  final BridgeAccountDetail_Acp _self;
  final $Res Function(BridgeAccountDetail_Acp) _then;

/// Create a copy of BridgeAccountDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeAccountDetail_Acp(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeAcpAccountSettings,
  ));
}


}

/// @nodoc
mixin _$BridgeAccountDomainFrame {

 BridgeResourceStamp get stamp;
/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountDomainFrameCopyWith<BridgeAccountDomainFrame> get copyWith => _$BridgeAccountDomainFrameCopyWithImpl<BridgeAccountDomainFrame>(this as BridgeAccountDomainFrame, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAccountDomainFrame;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountDomainFrame&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp));
}


@override
int get hashCode {
  final _this = this as BridgeAccountDomainFrame;
  return Object.hash(runtimeType,_this.stamp);
}

@override
String toString() {
  final _this = this as BridgeAccountDomainFrame;
  return 'BridgeAccountDomainFrame(stamp: ${_this.stamp})';
}


}

/// @nodoc
abstract mixin class $BridgeAccountDomainFrameCopyWith<$Res>  {
  factory $BridgeAccountDomainFrameCopyWith(BridgeAccountDomainFrame value, $Res Function(BridgeAccountDomainFrame) _then) = _$BridgeAccountDomainFrameCopyWithImpl;
@useResult
$Res call({
 BridgeResourceStamp stamp
});




}
/// @nodoc
class _$BridgeAccountDomainFrameCopyWithImpl<$Res>
    implements $BridgeAccountDomainFrameCopyWith<$Res> {
  _$BridgeAccountDomainFrameCopyWithImpl(this._self, this._then);

  final BridgeAccountDomainFrame _self;
  final $Res Function(BridgeAccountDomainFrame) _then;

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeResourceStamp,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAccountDomainFrame].
extension BridgeAccountDomainFramePatterns on BridgeAccountDomainFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountDomainFrame_Summaries value)?  summaries,TResult Function( BridgeAccountDomainFrame_Detail value)?  detail,TResult Function( BridgeAccountDomainFrame_Models value)?  models,TResult Function( BridgeAccountDomainFrame_Usage value)?  usage,TResult Function( BridgeAccountDomainFrame_AcpAuth value)?  acpAuth,TResult Function( BridgeAccountDomainFrame_AcpInstall value)?  acpInstall,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountDomainFrame_Summaries() when summaries != null:
return summaries(_that);case BridgeAccountDomainFrame_Detail() when detail != null:
return detail(_that);case BridgeAccountDomainFrame_Models() when models != null:
return models(_that);case BridgeAccountDomainFrame_Usage() when usage != null:
return usage(_that);case BridgeAccountDomainFrame_AcpAuth() when acpAuth != null:
return acpAuth(_that);case BridgeAccountDomainFrame_AcpInstall() when acpInstall != null:
return acpInstall(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountDomainFrame_Summaries value)  summaries,required TResult Function( BridgeAccountDomainFrame_Detail value)  detail,required TResult Function( BridgeAccountDomainFrame_Models value)  models,required TResult Function( BridgeAccountDomainFrame_Usage value)  usage,required TResult Function( BridgeAccountDomainFrame_AcpAuth value)  acpAuth,required TResult Function( BridgeAccountDomainFrame_AcpInstall value)  acpInstall,}){
final _that = this;
switch (_that) {
case BridgeAccountDomainFrame_Summaries():
return summaries(_that);case BridgeAccountDomainFrame_Detail():
return detail(_that);case BridgeAccountDomainFrame_Models():
return models(_that);case BridgeAccountDomainFrame_Usage():
return usage(_that);case BridgeAccountDomainFrame_AcpAuth():
return acpAuth(_that);case BridgeAccountDomainFrame_AcpInstall():
return acpInstall(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountDomainFrame_Summaries value)?  summaries,TResult? Function( BridgeAccountDomainFrame_Detail value)?  detail,TResult? Function( BridgeAccountDomainFrame_Models value)?  models,TResult? Function( BridgeAccountDomainFrame_Usage value)?  usage,TResult? Function( BridgeAccountDomainFrame_AcpAuth value)?  acpAuth,TResult? Function( BridgeAccountDomainFrame_AcpInstall value)?  acpInstall,}){
final _that = this;
switch (_that) {
case BridgeAccountDomainFrame_Summaries() when summaries != null:
return summaries(_that);case BridgeAccountDomainFrame_Detail() when detail != null:
return detail(_that);case BridgeAccountDomainFrame_Models() when models != null:
return models(_that);case BridgeAccountDomainFrame_Usage() when usage != null:
return usage(_that);case BridgeAccountDomainFrame_AcpAuth() when acpAuth != null:
return acpAuth(_that);case BridgeAccountDomainFrame_AcpInstall() when acpInstall != null:
return acpInstall(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeResourceStamp stamp,  List<BridgeAccountSummary> accounts)?  summaries,TResult Function( BridgeResourceStamp stamp,  BridgeAccountIdentity identity,  BridgeAccountDetail? account)?  detail,TResult Function( BridgeResourceStamp stamp,  String accountId,  BridgeModelCatalogAccountDto? catalog)?  models,TResult Function( BridgeResourceStamp stamp,  List<BridgeAccountUsageObservation> accounts)?  usage,TResult Function( BridgeResourceStamp stamp,  BridgeAcpAuthSnapshot snapshot)?  acpAuth,TResult Function( BridgeResourceStamp stamp,  BridgeAcpInstallSnapshot snapshot)?  acpInstall,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountDomainFrame_Summaries() when summaries != null:
return summaries(_that.stamp,_that.accounts);case BridgeAccountDomainFrame_Detail() when detail != null:
return detail(_that.stamp,_that.identity,_that.account);case BridgeAccountDomainFrame_Models() when models != null:
return models(_that.stamp,_that.accountId,_that.catalog);case BridgeAccountDomainFrame_Usage() when usage != null:
return usage(_that.stamp,_that.accounts);case BridgeAccountDomainFrame_AcpAuth() when acpAuth != null:
return acpAuth(_that.stamp,_that.snapshot);case BridgeAccountDomainFrame_AcpInstall() when acpInstall != null:
return acpInstall(_that.stamp,_that.snapshot);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeResourceStamp stamp,  List<BridgeAccountSummary> accounts)  summaries,required TResult Function( BridgeResourceStamp stamp,  BridgeAccountIdentity identity,  BridgeAccountDetail? account)  detail,required TResult Function( BridgeResourceStamp stamp,  String accountId,  BridgeModelCatalogAccountDto? catalog)  models,required TResult Function( BridgeResourceStamp stamp,  List<BridgeAccountUsageObservation> accounts)  usage,required TResult Function( BridgeResourceStamp stamp,  BridgeAcpAuthSnapshot snapshot)  acpAuth,required TResult Function( BridgeResourceStamp stamp,  BridgeAcpInstallSnapshot snapshot)  acpInstall,}) {final _that = this;
switch (_that) {
case BridgeAccountDomainFrame_Summaries():
return summaries(_that.stamp,_that.accounts);case BridgeAccountDomainFrame_Detail():
return detail(_that.stamp,_that.identity,_that.account);case BridgeAccountDomainFrame_Models():
return models(_that.stamp,_that.accountId,_that.catalog);case BridgeAccountDomainFrame_Usage():
return usage(_that.stamp,_that.accounts);case BridgeAccountDomainFrame_AcpAuth():
return acpAuth(_that.stamp,_that.snapshot);case BridgeAccountDomainFrame_AcpInstall():
return acpInstall(_that.stamp,_that.snapshot);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeResourceStamp stamp,  List<BridgeAccountSummary> accounts)?  summaries,TResult? Function( BridgeResourceStamp stamp,  BridgeAccountIdentity identity,  BridgeAccountDetail? account)?  detail,TResult? Function( BridgeResourceStamp stamp,  String accountId,  BridgeModelCatalogAccountDto? catalog)?  models,TResult? Function( BridgeResourceStamp stamp,  List<BridgeAccountUsageObservation> accounts)?  usage,TResult? Function( BridgeResourceStamp stamp,  BridgeAcpAuthSnapshot snapshot)?  acpAuth,TResult? Function( BridgeResourceStamp stamp,  BridgeAcpInstallSnapshot snapshot)?  acpInstall,}) {final _that = this;
switch (_that) {
case BridgeAccountDomainFrame_Summaries() when summaries != null:
return summaries(_that.stamp,_that.accounts);case BridgeAccountDomainFrame_Detail() when detail != null:
return detail(_that.stamp,_that.identity,_that.account);case BridgeAccountDomainFrame_Models() when models != null:
return models(_that.stamp,_that.accountId,_that.catalog);case BridgeAccountDomainFrame_Usage() when usage != null:
return usage(_that.stamp,_that.accounts);case BridgeAccountDomainFrame_AcpAuth() when acpAuth != null:
return acpAuth(_that.stamp,_that.snapshot);case BridgeAccountDomainFrame_AcpInstall() when acpInstall != null:
return acpInstall(_that.stamp,_that.snapshot);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountDomainFrame_Summaries extends BridgeAccountDomainFrame {
  const BridgeAccountDomainFrame_Summaries({required this.stamp, required  List<BridgeAccountSummary> accounts}): _accounts = accounts,super._();


@override final  BridgeResourceStamp stamp;
 final  List<BridgeAccountSummary> _accounts;
 List<BridgeAccountSummary> get accounts {
  if (_accounts is EqualUnmodifiableListView) return _accounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_accounts);
}


/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountDomainFrame_SummariesCopyWith<BridgeAccountDomainFrame_Summaries> get copyWith => _$BridgeAccountDomainFrame_SummariesCopyWithImpl<BridgeAccountDomainFrame_Summaries>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountDomainFrame_Summaries&&(identical(other.stamp, stamp) || other.stamp == stamp)&&const DeepCollectionEquality().equals(other.accounts, _accounts));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,const DeepCollectionEquality().hash(_accounts));
}

@override
String toString() {
    return 'BridgeAccountDomainFrame.summaries(stamp: $stamp, accounts: $accounts)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountDomainFrame_SummariesCopyWith<$Res> implements $BridgeAccountDomainFrameCopyWith<$Res> {
  factory $BridgeAccountDomainFrame_SummariesCopyWith(BridgeAccountDomainFrame_Summaries value, $Res Function(BridgeAccountDomainFrame_Summaries) _then) = _$BridgeAccountDomainFrame_SummariesCopyWithImpl;
@override @useResult
$Res call({
 BridgeResourceStamp stamp, List<BridgeAccountSummary> accounts
});




}
/// @nodoc
class _$BridgeAccountDomainFrame_SummariesCopyWithImpl<$Res>
    implements $BridgeAccountDomainFrame_SummariesCopyWith<$Res> {
  _$BridgeAccountDomainFrame_SummariesCopyWithImpl(this._self, this._then);

  final BridgeAccountDomainFrame_Summaries _self;
  final $Res Function(BridgeAccountDomainFrame_Summaries) _then;

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? accounts = null,}) {
  return _then(BridgeAccountDomainFrame_Summaries(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeResourceStamp,accounts: null == accounts ? _self._accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<BridgeAccountSummary>,
  ));
}


}

/// @nodoc


class BridgeAccountDomainFrame_Detail extends BridgeAccountDomainFrame {
  const BridgeAccountDomainFrame_Detail({required this.stamp, required this.identity, this.account}): super._();


@override final  BridgeResourceStamp stamp;
 final  BridgeAccountIdentity identity;
 final  BridgeAccountDetail? account;

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountDomainFrame_DetailCopyWith<BridgeAccountDomainFrame_Detail> get copyWith => _$BridgeAccountDomainFrame_DetailCopyWithImpl<BridgeAccountDomainFrame_Detail>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountDomainFrame_Detail&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.account, account) || other.account == account));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,identity,account);
}

@override
String toString() {
    return 'BridgeAccountDomainFrame.detail(stamp: $stamp, identity: $identity, account: $account)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountDomainFrame_DetailCopyWith<$Res> implements $BridgeAccountDomainFrameCopyWith<$Res> {
  factory $BridgeAccountDomainFrame_DetailCopyWith(BridgeAccountDomainFrame_Detail value, $Res Function(BridgeAccountDomainFrame_Detail) _then) = _$BridgeAccountDomainFrame_DetailCopyWithImpl;
@override @useResult
$Res call({
 BridgeResourceStamp stamp, BridgeAccountIdentity identity, BridgeAccountDetail? account
});


$BridgeAccountIdentityCopyWith<$Res> get identity;$BridgeAccountDetailCopyWith<$Res>? get account;

}
/// @nodoc
class _$BridgeAccountDomainFrame_DetailCopyWithImpl<$Res>
    implements $BridgeAccountDomainFrame_DetailCopyWith<$Res> {
  _$BridgeAccountDomainFrame_DetailCopyWithImpl(this._self, this._then);

  final BridgeAccountDomainFrame_Detail _self;
  final $Res Function(BridgeAccountDomainFrame_Detail) _then;

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? identity = null,Object? account = freezed,}) {
  return _then(BridgeAccountDomainFrame_Detail(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeResourceStamp,identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeAccountIdentity,account: freezed == account ? _self.account : account // ignore: cast_nullable_to_non_nullable
as BridgeAccountDetail?,
  ));
}

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAccountIdentityCopyWith<$Res> get identity {

  return $BridgeAccountIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAccountDetailCopyWith<$Res>? get account {
    if (_self.account == null) {
    return null;
  }

  return $BridgeAccountDetailCopyWith<$Res>(_self.account!, (value) {
    return _then(_self.copyWith(account: value));
  });
}
}

/// @nodoc


class BridgeAccountDomainFrame_Models extends BridgeAccountDomainFrame {
  const BridgeAccountDomainFrame_Models({required this.stamp, required this.accountId, this.catalog}): super._();


@override final  BridgeResourceStamp stamp;
 final  String accountId;
 final  BridgeModelCatalogAccountDto? catalog;

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountDomainFrame_ModelsCopyWith<BridgeAccountDomainFrame_Models> get copyWith => _$BridgeAccountDomainFrame_ModelsCopyWithImpl<BridgeAccountDomainFrame_Models>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountDomainFrame_Models&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.catalog, catalog) || other.catalog == catalog));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,accountId,catalog);
}

@override
String toString() {
    return 'BridgeAccountDomainFrame.models(stamp: $stamp, accountId: $accountId, catalog: $catalog)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountDomainFrame_ModelsCopyWith<$Res> implements $BridgeAccountDomainFrameCopyWith<$Res> {
  factory $BridgeAccountDomainFrame_ModelsCopyWith(BridgeAccountDomainFrame_Models value, $Res Function(BridgeAccountDomainFrame_Models) _then) = _$BridgeAccountDomainFrame_ModelsCopyWithImpl;
@override @useResult
$Res call({
 BridgeResourceStamp stamp, String accountId, BridgeModelCatalogAccountDto? catalog
});




}
/// @nodoc
class _$BridgeAccountDomainFrame_ModelsCopyWithImpl<$Res>
    implements $BridgeAccountDomainFrame_ModelsCopyWith<$Res> {
  _$BridgeAccountDomainFrame_ModelsCopyWithImpl(this._self, this._then);

  final BridgeAccountDomainFrame_Models _self;
  final $Res Function(BridgeAccountDomainFrame_Models) _then;

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? accountId = null,Object? catalog = freezed,}) {
  return _then(BridgeAccountDomainFrame_Models(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeResourceStamp,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,catalog: freezed == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as BridgeModelCatalogAccountDto?,
  ));
}


}

/// @nodoc


class BridgeAccountDomainFrame_Usage extends BridgeAccountDomainFrame {
  const BridgeAccountDomainFrame_Usage({required this.stamp, required  List<BridgeAccountUsageObservation> accounts}): _accounts = accounts,super._();


@override final  BridgeResourceStamp stamp;
 final  List<BridgeAccountUsageObservation> _accounts;
 List<BridgeAccountUsageObservation> get accounts {
  if (_accounts is EqualUnmodifiableListView) return _accounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_accounts);
}


/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountDomainFrame_UsageCopyWith<BridgeAccountDomainFrame_Usage> get copyWith => _$BridgeAccountDomainFrame_UsageCopyWithImpl<BridgeAccountDomainFrame_Usage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountDomainFrame_Usage&&(identical(other.stamp, stamp) || other.stamp == stamp)&&const DeepCollectionEquality().equals(other.accounts, _accounts));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,const DeepCollectionEquality().hash(_accounts));
}

@override
String toString() {
    return 'BridgeAccountDomainFrame.usage(stamp: $stamp, accounts: $accounts)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountDomainFrame_UsageCopyWith<$Res> implements $BridgeAccountDomainFrameCopyWith<$Res> {
  factory $BridgeAccountDomainFrame_UsageCopyWith(BridgeAccountDomainFrame_Usage value, $Res Function(BridgeAccountDomainFrame_Usage) _then) = _$BridgeAccountDomainFrame_UsageCopyWithImpl;
@override @useResult
$Res call({
 BridgeResourceStamp stamp, List<BridgeAccountUsageObservation> accounts
});




}
/// @nodoc
class _$BridgeAccountDomainFrame_UsageCopyWithImpl<$Res>
    implements $BridgeAccountDomainFrame_UsageCopyWith<$Res> {
  _$BridgeAccountDomainFrame_UsageCopyWithImpl(this._self, this._then);

  final BridgeAccountDomainFrame_Usage _self;
  final $Res Function(BridgeAccountDomainFrame_Usage) _then;

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? accounts = null,}) {
  return _then(BridgeAccountDomainFrame_Usage(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeResourceStamp,accounts: null == accounts ? _self._accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<BridgeAccountUsageObservation>,
  ));
}


}

/// @nodoc


class BridgeAccountDomainFrame_AcpAuth extends BridgeAccountDomainFrame {
  const BridgeAccountDomainFrame_AcpAuth({required this.stamp, required this.snapshot}): super._();


@override final  BridgeResourceStamp stamp;
 final  BridgeAcpAuthSnapshot snapshot;

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountDomainFrame_AcpAuthCopyWith<BridgeAccountDomainFrame_AcpAuth> get copyWith => _$BridgeAccountDomainFrame_AcpAuthCopyWithImpl<BridgeAccountDomainFrame_AcpAuth>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountDomainFrame_AcpAuth&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,snapshot);
}

@override
String toString() {
    return 'BridgeAccountDomainFrame.acpAuth(stamp: $stamp, snapshot: $snapshot)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountDomainFrame_AcpAuthCopyWith<$Res> implements $BridgeAccountDomainFrameCopyWith<$Res> {
  factory $BridgeAccountDomainFrame_AcpAuthCopyWith(BridgeAccountDomainFrame_AcpAuth value, $Res Function(BridgeAccountDomainFrame_AcpAuth) _then) = _$BridgeAccountDomainFrame_AcpAuthCopyWithImpl;
@override @useResult
$Res call({
 BridgeResourceStamp stamp, BridgeAcpAuthSnapshot snapshot
});




}
/// @nodoc
class _$BridgeAccountDomainFrame_AcpAuthCopyWithImpl<$Res>
    implements $BridgeAccountDomainFrame_AcpAuthCopyWith<$Res> {
  _$BridgeAccountDomainFrame_AcpAuthCopyWithImpl(this._self, this._then);

  final BridgeAccountDomainFrame_AcpAuth _self;
  final $Res Function(BridgeAccountDomainFrame_AcpAuth) _then;

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? snapshot = null,}) {
  return _then(BridgeAccountDomainFrame_AcpAuth(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeResourceStamp,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as BridgeAcpAuthSnapshot,
  ));
}


}

/// @nodoc


class BridgeAccountDomainFrame_AcpInstall extends BridgeAccountDomainFrame {
  const BridgeAccountDomainFrame_AcpInstall({required this.stamp, required this.snapshot}): super._();


@override final  BridgeResourceStamp stamp;
 final  BridgeAcpInstallSnapshot snapshot;

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountDomainFrame_AcpInstallCopyWith<BridgeAccountDomainFrame_AcpInstall> get copyWith => _$BridgeAccountDomainFrame_AcpInstallCopyWithImpl<BridgeAccountDomainFrame_AcpInstall>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountDomainFrame_AcpInstall&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,snapshot);
}

@override
String toString() {
    return 'BridgeAccountDomainFrame.acpInstall(stamp: $stamp, snapshot: $snapshot)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountDomainFrame_AcpInstallCopyWith<$Res> implements $BridgeAccountDomainFrameCopyWith<$Res> {
  factory $BridgeAccountDomainFrame_AcpInstallCopyWith(BridgeAccountDomainFrame_AcpInstall value, $Res Function(BridgeAccountDomainFrame_AcpInstall) _then) = _$BridgeAccountDomainFrame_AcpInstallCopyWithImpl;
@override @useResult
$Res call({
 BridgeResourceStamp stamp, BridgeAcpInstallSnapshot snapshot
});




}
/// @nodoc
class _$BridgeAccountDomainFrame_AcpInstallCopyWithImpl<$Res>
    implements $BridgeAccountDomainFrame_AcpInstallCopyWith<$Res> {
  _$BridgeAccountDomainFrame_AcpInstallCopyWithImpl(this._self, this._then);

  final BridgeAccountDomainFrame_AcpInstall _self;
  final $Res Function(BridgeAccountDomainFrame_AcpInstall) _then;

/// Create a copy of BridgeAccountDomainFrame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? snapshot = null,}) {
  return _then(BridgeAccountDomainFrame_AcpInstall(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeResourceStamp,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as BridgeAcpInstallSnapshot,
  ));
}


}

/// @nodoc
mixin _$BridgeAccountIdentity {

 String get accountId;
/// Create a copy of BridgeAccountIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountIdentityCopyWith<BridgeAccountIdentity> get copyWith => _$BridgeAccountIdentityCopyWithImpl<BridgeAccountIdentity>(this as BridgeAccountIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAccountIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountIdentity&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId));
}


@override
int get hashCode {
  final _this = this as BridgeAccountIdentity;
  return Object.hash(runtimeType,_this.accountId);
}

@override
String toString() {
  final _this = this as BridgeAccountIdentity;
  return 'BridgeAccountIdentity(accountId: ${_this.accountId})';
}


}

/// @nodoc
abstract mixin class $BridgeAccountIdentityCopyWith<$Res>  {
  factory $BridgeAccountIdentityCopyWith(BridgeAccountIdentity value, $Res Function(BridgeAccountIdentity) _then) = _$BridgeAccountIdentityCopyWithImpl;
@useResult
$Res call({
 String accountId
});




}
/// @nodoc
class _$BridgeAccountIdentityCopyWithImpl<$Res>
    implements $BridgeAccountIdentityCopyWith<$Res> {
  _$BridgeAccountIdentityCopyWithImpl(this._self, this._then);

  final BridgeAccountIdentity _self;
  final $Res Function(BridgeAccountIdentity) _then;

/// Create a copy of BridgeAccountIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,}) {
  return _then(_self.copyWith(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAccountIdentity].
extension BridgeAccountIdentityPatterns on BridgeAccountIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountIdentity_Native value)?  native,TResult Function( BridgeAccountIdentity_Acp value)?  acp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountIdentity_Native() when native != null:
return native(_that);case BridgeAccountIdentity_Acp() when acp != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountIdentity_Native value)  native,required TResult Function( BridgeAccountIdentity_Acp value)  acp,}){
final _that = this;
switch (_that) {
case BridgeAccountIdentity_Native():
return native(_that);case BridgeAccountIdentity_Acp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountIdentity_Native value)?  native,TResult? Function( BridgeAccountIdentity_Acp value)?  acp,}){
final _that = this;
switch (_that) {
case BridgeAccountIdentity_Native() when native != null:
return native(_that);case BridgeAccountIdentity_Acp() when acp != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String accountId)?  native,TResult Function( String accountId)?  acp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountIdentity_Native() when native != null:
return native(_that.accountId);case BridgeAccountIdentity_Acp() when acp != null:
return acp(_that.accountId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String accountId)  native,required TResult Function( String accountId)  acp,}) {final _that = this;
switch (_that) {
case BridgeAccountIdentity_Native():
return native(_that.accountId);case BridgeAccountIdentity_Acp():
return acp(_that.accountId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String accountId)?  native,TResult? Function( String accountId)?  acp,}) {final _that = this;
switch (_that) {
case BridgeAccountIdentity_Native() when native != null:
return native(_that.accountId);case BridgeAccountIdentity_Acp() when acp != null:
return acp(_that.accountId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountIdentity_Native extends BridgeAccountIdentity {
  const BridgeAccountIdentity_Native({required this.accountId}): super._();


@override final  String accountId;

/// Create a copy of BridgeAccountIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountIdentity_NativeCopyWith<BridgeAccountIdentity_Native> get copyWith => _$BridgeAccountIdentity_NativeCopyWithImpl<BridgeAccountIdentity_Native>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountIdentity_Native&&(identical(other.accountId, accountId) || other.accountId == accountId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId);
}

@override
String toString() {
    return 'BridgeAccountIdentity.native(accountId: $accountId)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountIdentity_NativeCopyWith<$Res> implements $BridgeAccountIdentityCopyWith<$Res> {
  factory $BridgeAccountIdentity_NativeCopyWith(BridgeAccountIdentity_Native value, $Res Function(BridgeAccountIdentity_Native) _then) = _$BridgeAccountIdentity_NativeCopyWithImpl;
@override @useResult
$Res call({
 String accountId
});




}
/// @nodoc
class _$BridgeAccountIdentity_NativeCopyWithImpl<$Res>
    implements $BridgeAccountIdentity_NativeCopyWith<$Res> {
  _$BridgeAccountIdentity_NativeCopyWithImpl(this._self, this._then);

  final BridgeAccountIdentity_Native _self;
  final $Res Function(BridgeAccountIdentity_Native) _then;

/// Create a copy of BridgeAccountIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,}) {
  return _then(BridgeAccountIdentity_Native(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAccountIdentity_Acp extends BridgeAccountIdentity {
  const BridgeAccountIdentity_Acp({required this.accountId}): super._();


@override final  String accountId;

/// Create a copy of BridgeAccountIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountIdentity_AcpCopyWith<BridgeAccountIdentity_Acp> get copyWith => _$BridgeAccountIdentity_AcpCopyWithImpl<BridgeAccountIdentity_Acp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountIdentity_Acp&&(identical(other.accountId, accountId) || other.accountId == accountId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId);
}

@override
String toString() {
    return 'BridgeAccountIdentity.acp(accountId: $accountId)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountIdentity_AcpCopyWith<$Res> implements $BridgeAccountIdentityCopyWith<$Res> {
  factory $BridgeAccountIdentity_AcpCopyWith(BridgeAccountIdentity_Acp value, $Res Function(BridgeAccountIdentity_Acp) _then) = _$BridgeAccountIdentity_AcpCopyWithImpl;
@override @useResult
$Res call({
 String accountId
});




}
/// @nodoc
class _$BridgeAccountIdentity_AcpCopyWithImpl<$Res>
    implements $BridgeAccountIdentity_AcpCopyWith<$Res> {
  _$BridgeAccountIdentity_AcpCopyWithImpl(this._self, this._then);

  final BridgeAccountIdentity_Acp _self;
  final $Res Function(BridgeAccountIdentity_Acp) _then;

/// Create a copy of BridgeAccountIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,}) {
  return _then(BridgeAccountIdentity_Acp(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeAccountModelsPatch {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountModelsPatch);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountModelsPatch()';
}


}

/// @nodoc
class $BridgeAccountModelsPatchCopyWith<$Res>  {
$BridgeAccountModelsPatchCopyWith(BridgeAccountModelsPatch _, $Res Function(BridgeAccountModelsPatch) __);
}


/// Adds pattern-matching-related methods to [BridgeAccountModelsPatch].
extension BridgeAccountModelsPatchPatterns on BridgeAccountModelsPatch {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountModelsPatch_Keep value)?  keep,TResult Function( BridgeAccountModelsPatch_Set value)?  set_,TResult Function( BridgeAccountModelsPatch_Restore value)?  restore,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountModelsPatch_Keep() when keep != null:
return keep(_that);case BridgeAccountModelsPatch_Set() when set_ != null:
return set_(_that);case BridgeAccountModelsPatch_Restore() when restore != null:
return restore(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountModelsPatch_Keep value)  keep,required TResult Function( BridgeAccountModelsPatch_Set value)  set_,required TResult Function( BridgeAccountModelsPatch_Restore value)  restore,}){
final _that = this;
switch (_that) {
case BridgeAccountModelsPatch_Keep():
return keep(_that);case BridgeAccountModelsPatch_Set():
return set_(_that);case BridgeAccountModelsPatch_Restore():
return restore(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountModelsPatch_Keep value)?  keep,TResult? Function( BridgeAccountModelsPatch_Set value)?  set_,TResult? Function( BridgeAccountModelsPatch_Restore value)?  restore,}){
final _that = this;
switch (_that) {
case BridgeAccountModelsPatch_Keep() when keep != null:
return keep(_that);case BridgeAccountModelsPatch_Set() when set_ != null:
return set_(_that);case BridgeAccountModelsPatch_Restore() when restore != null:
return restore(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  keep,TResult Function( List<AccountModelInput> models)?  set_,TResult Function()?  restore,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountModelsPatch_Keep() when keep != null:
return keep();case BridgeAccountModelsPatch_Set() when set_ != null:
return set_(_that.models);case BridgeAccountModelsPatch_Restore() when restore != null:
return restore();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  keep,required TResult Function( List<AccountModelInput> models)  set_,required TResult Function()  restore,}) {final _that = this;
switch (_that) {
case BridgeAccountModelsPatch_Keep():
return keep();case BridgeAccountModelsPatch_Set():
return set_(_that.models);case BridgeAccountModelsPatch_Restore():
return restore();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  keep,TResult? Function( List<AccountModelInput> models)?  set_,TResult? Function()?  restore,}) {final _that = this;
switch (_that) {
case BridgeAccountModelsPatch_Keep() when keep != null:
return keep();case BridgeAccountModelsPatch_Set() when set_ != null:
return set_(_that.models);case BridgeAccountModelsPatch_Restore() when restore != null:
return restore();case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountModelsPatch_Keep extends BridgeAccountModelsPatch {
  const BridgeAccountModelsPatch_Keep(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountModelsPatch_Keep);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountModelsPatch.keep()';
}


}




/// @nodoc


class BridgeAccountModelsPatch_Set extends BridgeAccountModelsPatch {
  const BridgeAccountModelsPatch_Set({required  List<AccountModelInput> models}): _models = models,super._();


 final  List<AccountModelInput> _models;
 List<AccountModelInput> get models {
  if (_models is EqualUnmodifiableListView) return _models;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_models);
}


/// Create a copy of BridgeAccountModelsPatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountModelsPatch_SetCopyWith<BridgeAccountModelsPatch_Set> get copyWith => _$BridgeAccountModelsPatch_SetCopyWithImpl<BridgeAccountModelsPatch_Set>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountModelsPatch_Set&&const DeepCollectionEquality().equals(other.models, _models));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_models));
}

@override
String toString() {
    return 'BridgeAccountModelsPatch.set_(models: $models)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountModelsPatch_SetCopyWith<$Res> implements $BridgeAccountModelsPatchCopyWith<$Res> {
  factory $BridgeAccountModelsPatch_SetCopyWith(BridgeAccountModelsPatch_Set value, $Res Function(BridgeAccountModelsPatch_Set) _then) = _$BridgeAccountModelsPatch_SetCopyWithImpl;
@useResult
$Res call({
 List<AccountModelInput> models
});




}
/// @nodoc
class _$BridgeAccountModelsPatch_SetCopyWithImpl<$Res>
    implements $BridgeAccountModelsPatch_SetCopyWith<$Res> {
  _$BridgeAccountModelsPatch_SetCopyWithImpl(this._self, this._then);

  final BridgeAccountModelsPatch_Set _self;
  final $Res Function(BridgeAccountModelsPatch_Set) _then;

/// Create a copy of BridgeAccountModelsPatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? models = null,}) {
  return _then(BridgeAccountModelsPatch_Set(
models: null == models ? _self._models : models // ignore: cast_nullable_to_non_nullable
as List<AccountModelInput>,
  ));
}


}

/// @nodoc


class BridgeAccountModelsPatch_Restore extends BridgeAccountModelsPatch {
  const BridgeAccountModelsPatch_Restore(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountModelsPatch_Restore);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountModelsPatch.restore()';
}


}




/// @nodoc
mixin _$BridgeAccountObservationTarget {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountObservationTarget);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountObservationTarget()';
}


}

/// @nodoc
class $BridgeAccountObservationTargetCopyWith<$Res>  {
$BridgeAccountObservationTargetCopyWith(BridgeAccountObservationTarget _, $Res Function(BridgeAccountObservationTarget) __);
}


/// Adds pattern-matching-related methods to [BridgeAccountObservationTarget].
extension BridgeAccountObservationTargetPatterns on BridgeAccountObservationTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountObservationTarget_Summaries value)?  summaries,TResult Function( BridgeAccountObservationTarget_Detail value)?  detail,TResult Function( BridgeAccountObservationTarget_Models value)?  models,TResult Function( BridgeAccountObservationTarget_Usage value)?  usage,TResult Function( BridgeAccountObservationTarget_AcpAuth value)?  acpAuth,TResult Function( BridgeAccountObservationTarget_AcpInstall value)?  acpInstall,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountObservationTarget_Summaries() when summaries != null:
return summaries(_that);case BridgeAccountObservationTarget_Detail() when detail != null:
return detail(_that);case BridgeAccountObservationTarget_Models() when models != null:
return models(_that);case BridgeAccountObservationTarget_Usage() when usage != null:
return usage(_that);case BridgeAccountObservationTarget_AcpAuth() when acpAuth != null:
return acpAuth(_that);case BridgeAccountObservationTarget_AcpInstall() when acpInstall != null:
return acpInstall(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountObservationTarget_Summaries value)  summaries,required TResult Function( BridgeAccountObservationTarget_Detail value)  detail,required TResult Function( BridgeAccountObservationTarget_Models value)  models,required TResult Function( BridgeAccountObservationTarget_Usage value)  usage,required TResult Function( BridgeAccountObservationTarget_AcpAuth value)  acpAuth,required TResult Function( BridgeAccountObservationTarget_AcpInstall value)  acpInstall,}){
final _that = this;
switch (_that) {
case BridgeAccountObservationTarget_Summaries():
return summaries(_that);case BridgeAccountObservationTarget_Detail():
return detail(_that);case BridgeAccountObservationTarget_Models():
return models(_that);case BridgeAccountObservationTarget_Usage():
return usage(_that);case BridgeAccountObservationTarget_AcpAuth():
return acpAuth(_that);case BridgeAccountObservationTarget_AcpInstall():
return acpInstall(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountObservationTarget_Summaries value)?  summaries,TResult? Function( BridgeAccountObservationTarget_Detail value)?  detail,TResult? Function( BridgeAccountObservationTarget_Models value)?  models,TResult? Function( BridgeAccountObservationTarget_Usage value)?  usage,TResult? Function( BridgeAccountObservationTarget_AcpAuth value)?  acpAuth,TResult? Function( BridgeAccountObservationTarget_AcpInstall value)?  acpInstall,}){
final _that = this;
switch (_that) {
case BridgeAccountObservationTarget_Summaries() when summaries != null:
return summaries(_that);case BridgeAccountObservationTarget_Detail() when detail != null:
return detail(_that);case BridgeAccountObservationTarget_Models() when models != null:
return models(_that);case BridgeAccountObservationTarget_Usage() when usage != null:
return usage(_that);case BridgeAccountObservationTarget_AcpAuth() when acpAuth != null:
return acpAuth(_that);case BridgeAccountObservationTarget_AcpInstall() when acpInstall != null:
return acpInstall(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  summaries,TResult Function( BridgeAccountIdentity identity)?  detail,TResult Function( String accountId)?  models,TResult Function()?  usage,TResult Function()?  acpAuth,TResult Function()?  acpInstall,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountObservationTarget_Summaries() when summaries != null:
return summaries();case BridgeAccountObservationTarget_Detail() when detail != null:
return detail(_that.identity);case BridgeAccountObservationTarget_Models() when models != null:
return models(_that.accountId);case BridgeAccountObservationTarget_Usage() when usage != null:
return usage();case BridgeAccountObservationTarget_AcpAuth() when acpAuth != null:
return acpAuth();case BridgeAccountObservationTarget_AcpInstall() when acpInstall != null:
return acpInstall();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  summaries,required TResult Function( BridgeAccountIdentity identity)  detail,required TResult Function( String accountId)  models,required TResult Function()  usage,required TResult Function()  acpAuth,required TResult Function()  acpInstall,}) {final _that = this;
switch (_that) {
case BridgeAccountObservationTarget_Summaries():
return summaries();case BridgeAccountObservationTarget_Detail():
return detail(_that.identity);case BridgeAccountObservationTarget_Models():
return models(_that.accountId);case BridgeAccountObservationTarget_Usage():
return usage();case BridgeAccountObservationTarget_AcpAuth():
return acpAuth();case BridgeAccountObservationTarget_AcpInstall():
return acpInstall();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  summaries,TResult? Function( BridgeAccountIdentity identity)?  detail,TResult? Function( String accountId)?  models,TResult? Function()?  usage,TResult? Function()?  acpAuth,TResult? Function()?  acpInstall,}) {final _that = this;
switch (_that) {
case BridgeAccountObservationTarget_Summaries() when summaries != null:
return summaries();case BridgeAccountObservationTarget_Detail() when detail != null:
return detail(_that.identity);case BridgeAccountObservationTarget_Models() when models != null:
return models(_that.accountId);case BridgeAccountObservationTarget_Usage() when usage != null:
return usage();case BridgeAccountObservationTarget_AcpAuth() when acpAuth != null:
return acpAuth();case BridgeAccountObservationTarget_AcpInstall() when acpInstall != null:
return acpInstall();case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountObservationTarget_Summaries extends BridgeAccountObservationTarget {
  const BridgeAccountObservationTarget_Summaries(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountObservationTarget_Summaries);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountObservationTarget.summaries()';
}


}




/// @nodoc


class BridgeAccountObservationTarget_Detail extends BridgeAccountObservationTarget {
  const BridgeAccountObservationTarget_Detail({required this.identity}): super._();


 final  BridgeAccountIdentity identity;

/// Create a copy of BridgeAccountObservationTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountObservationTarget_DetailCopyWith<BridgeAccountObservationTarget_Detail> get copyWith => _$BridgeAccountObservationTarget_DetailCopyWithImpl<BridgeAccountObservationTarget_Detail>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountObservationTarget_Detail&&(identical(other.identity, identity) || other.identity == identity));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity);
}

@override
String toString() {
    return 'BridgeAccountObservationTarget.detail(identity: $identity)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountObservationTarget_DetailCopyWith<$Res> implements $BridgeAccountObservationTargetCopyWith<$Res> {
  factory $BridgeAccountObservationTarget_DetailCopyWith(BridgeAccountObservationTarget_Detail value, $Res Function(BridgeAccountObservationTarget_Detail) _then) = _$BridgeAccountObservationTarget_DetailCopyWithImpl;
@useResult
$Res call({
 BridgeAccountIdentity identity
});


$BridgeAccountIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$BridgeAccountObservationTarget_DetailCopyWithImpl<$Res>
    implements $BridgeAccountObservationTarget_DetailCopyWith<$Res> {
  _$BridgeAccountObservationTarget_DetailCopyWithImpl(this._self, this._then);

  final BridgeAccountObservationTarget_Detail _self;
  final $Res Function(BridgeAccountObservationTarget_Detail) _then;

/// Create a copy of BridgeAccountObservationTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,}) {
  return _then(BridgeAccountObservationTarget_Detail(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeAccountIdentity,
  ));
}

/// Create a copy of BridgeAccountObservationTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAccountIdentityCopyWith<$Res> get identity {

  return $BridgeAccountIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc


class BridgeAccountObservationTarget_Models extends BridgeAccountObservationTarget {
  const BridgeAccountObservationTarget_Models({required this.accountId}): super._();


 final  String accountId;

/// Create a copy of BridgeAccountObservationTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountObservationTarget_ModelsCopyWith<BridgeAccountObservationTarget_Models> get copyWith => _$BridgeAccountObservationTarget_ModelsCopyWithImpl<BridgeAccountObservationTarget_Models>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountObservationTarget_Models&&(identical(other.accountId, accountId) || other.accountId == accountId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId);
}

@override
String toString() {
    return 'BridgeAccountObservationTarget.models(accountId: $accountId)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountObservationTarget_ModelsCopyWith<$Res> implements $BridgeAccountObservationTargetCopyWith<$Res> {
  factory $BridgeAccountObservationTarget_ModelsCopyWith(BridgeAccountObservationTarget_Models value, $Res Function(BridgeAccountObservationTarget_Models) _then) = _$BridgeAccountObservationTarget_ModelsCopyWithImpl;
@useResult
$Res call({
 String accountId
});




}
/// @nodoc
class _$BridgeAccountObservationTarget_ModelsCopyWithImpl<$Res>
    implements $BridgeAccountObservationTarget_ModelsCopyWith<$Res> {
  _$BridgeAccountObservationTarget_ModelsCopyWithImpl(this._self, this._then);

  final BridgeAccountObservationTarget_Models _self;
  final $Res Function(BridgeAccountObservationTarget_Models) _then;

/// Create a copy of BridgeAccountObservationTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? accountId = null,}) {
  return _then(BridgeAccountObservationTarget_Models(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAccountObservationTarget_Usage extends BridgeAccountObservationTarget {
  const BridgeAccountObservationTarget_Usage(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountObservationTarget_Usage);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountObservationTarget.usage()';
}


}




/// @nodoc


class BridgeAccountObservationTarget_AcpAuth extends BridgeAccountObservationTarget {
  const BridgeAccountObservationTarget_AcpAuth(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountObservationTarget_AcpAuth);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountObservationTarget.acpAuth()';
}


}




/// @nodoc


class BridgeAccountObservationTarget_AcpInstall extends BridgeAccountObservationTarget {
  const BridgeAccountObservationTarget_AcpInstall(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountObservationTarget_AcpInstall);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountObservationTarget.acpInstall()';
}


}




/// @nodoc
mixin _$BridgeAccountQuotaWindow {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountQuotaWindow);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountQuotaWindow()';
}


}

/// @nodoc
class $BridgeAccountQuotaWindowCopyWith<$Res>  {
$BridgeAccountQuotaWindowCopyWith(BridgeAccountQuotaWindow _, $Res Function(BridgeAccountQuotaWindow) __);
}


/// Adds pattern-matching-related methods to [BridgeAccountQuotaWindow].
extension BridgeAccountQuotaWindowPatterns on BridgeAccountQuotaWindow {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountQuotaWindow_FiveHour value)?  fiveHour,TResult Function( BridgeAccountQuotaWindow_Weekly value)?  weekly,TResult Function( BridgeAccountQuotaWindow_McpMonthly value)?  mcpMonthly,TResult Function( BridgeAccountQuotaWindow_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountQuotaWindow_FiveHour() when fiveHour != null:
return fiveHour(_that);case BridgeAccountQuotaWindow_Weekly() when weekly != null:
return weekly(_that);case BridgeAccountQuotaWindow_McpMonthly() when mcpMonthly != null:
return mcpMonthly(_that);case BridgeAccountQuotaWindow_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountQuotaWindow_FiveHour value)  fiveHour,required TResult Function( BridgeAccountQuotaWindow_Weekly value)  weekly,required TResult Function( BridgeAccountQuotaWindow_McpMonthly value)  mcpMonthly,required TResult Function( BridgeAccountQuotaWindow_Other value)  other,}){
final _that = this;
switch (_that) {
case BridgeAccountQuotaWindow_FiveHour():
return fiveHour(_that);case BridgeAccountQuotaWindow_Weekly():
return weekly(_that);case BridgeAccountQuotaWindow_McpMonthly():
return mcpMonthly(_that);case BridgeAccountQuotaWindow_Other():
return other(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountQuotaWindow_FiveHour value)?  fiveHour,TResult? Function( BridgeAccountQuotaWindow_Weekly value)?  weekly,TResult? Function( BridgeAccountQuotaWindow_McpMonthly value)?  mcpMonthly,TResult? Function( BridgeAccountQuotaWindow_Other value)?  other,}){
final _that = this;
switch (_that) {
case BridgeAccountQuotaWindow_FiveHour() when fiveHour != null:
return fiveHour(_that);case BridgeAccountQuotaWindow_Weekly() when weekly != null:
return weekly(_that);case BridgeAccountQuotaWindow_McpMonthly() when mcpMonthly != null:
return mcpMonthly(_that);case BridgeAccountQuotaWindow_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  fiveHour,TResult Function()?  weekly,TResult Function()?  mcpMonthly,TResult Function( String field0)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountQuotaWindow_FiveHour() when fiveHour != null:
return fiveHour();case BridgeAccountQuotaWindow_Weekly() when weekly != null:
return weekly();case BridgeAccountQuotaWindow_McpMonthly() when mcpMonthly != null:
return mcpMonthly();case BridgeAccountQuotaWindow_Other() when other != null:
return other(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  fiveHour,required TResult Function()  weekly,required TResult Function()  mcpMonthly,required TResult Function( String field0)  other,}) {final _that = this;
switch (_that) {
case BridgeAccountQuotaWindow_FiveHour():
return fiveHour();case BridgeAccountQuotaWindow_Weekly():
return weekly();case BridgeAccountQuotaWindow_McpMonthly():
return mcpMonthly();case BridgeAccountQuotaWindow_Other():
return other(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  fiveHour,TResult? Function()?  weekly,TResult? Function()?  mcpMonthly,TResult? Function( String field0)?  other,}) {final _that = this;
switch (_that) {
case BridgeAccountQuotaWindow_FiveHour() when fiveHour != null:
return fiveHour();case BridgeAccountQuotaWindow_Weekly() when weekly != null:
return weekly();case BridgeAccountQuotaWindow_McpMonthly() when mcpMonthly != null:
return mcpMonthly();case BridgeAccountQuotaWindow_Other() when other != null:
return other(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountQuotaWindow_FiveHour extends BridgeAccountQuotaWindow {
  const BridgeAccountQuotaWindow_FiveHour(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountQuotaWindow_FiveHour);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountQuotaWindow.fiveHour()';
}


}




/// @nodoc


class BridgeAccountQuotaWindow_Weekly extends BridgeAccountQuotaWindow {
  const BridgeAccountQuotaWindow_Weekly(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountQuotaWindow_Weekly);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountQuotaWindow.weekly()';
}


}




/// @nodoc


class BridgeAccountQuotaWindow_McpMonthly extends BridgeAccountQuotaWindow {
  const BridgeAccountQuotaWindow_McpMonthly(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountQuotaWindow_McpMonthly);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountQuotaWindow.mcpMonthly()';
}


}




/// @nodoc


class BridgeAccountQuotaWindow_Other extends BridgeAccountQuotaWindow {
  const BridgeAccountQuotaWindow_Other(this.field0): super._();


 final  String field0;

/// Create a copy of BridgeAccountQuotaWindow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountQuotaWindow_OtherCopyWith<BridgeAccountQuotaWindow_Other> get copyWith => _$BridgeAccountQuotaWindow_OtherCopyWithImpl<BridgeAccountQuotaWindow_Other>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountQuotaWindow_Other&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeAccountQuotaWindow.other(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountQuotaWindow_OtherCopyWith<$Res> implements $BridgeAccountQuotaWindowCopyWith<$Res> {
  factory $BridgeAccountQuotaWindow_OtherCopyWith(BridgeAccountQuotaWindow_Other value, $Res Function(BridgeAccountQuotaWindow_Other) _then) = _$BridgeAccountQuotaWindow_OtherCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$BridgeAccountQuotaWindow_OtherCopyWithImpl<$Res>
    implements $BridgeAccountQuotaWindow_OtherCopyWith<$Res> {
  _$BridgeAccountQuotaWindow_OtherCopyWithImpl(this._self, this._then);

  final BridgeAccountQuotaWindow_Other _self;
  final $Res Function(BridgeAccountQuotaWindow_Other) _then;

/// Create a copy of BridgeAccountQuotaWindow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeAccountQuotaWindow_Other(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeAccountTextPatch {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTextPatch);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountTextPatch()';
}


}

/// @nodoc
class $BridgeAccountTextPatchCopyWith<$Res>  {
$BridgeAccountTextPatchCopyWith(BridgeAccountTextPatch _, $Res Function(BridgeAccountTextPatch) __);
}


/// Adds pattern-matching-related methods to [BridgeAccountTextPatch].
extension BridgeAccountTextPatchPatterns on BridgeAccountTextPatch {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountTextPatch_Keep value)?  keep,TResult Function( BridgeAccountTextPatch_Set value)?  set_,TResult Function( BridgeAccountTextPatch_Restore value)?  restore,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountTextPatch_Keep() when keep != null:
return keep(_that);case BridgeAccountTextPatch_Set() when set_ != null:
return set_(_that);case BridgeAccountTextPatch_Restore() when restore != null:
return restore(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountTextPatch_Keep value)  keep,required TResult Function( BridgeAccountTextPatch_Set value)  set_,required TResult Function( BridgeAccountTextPatch_Restore value)  restore,}){
final _that = this;
switch (_that) {
case BridgeAccountTextPatch_Keep():
return keep(_that);case BridgeAccountTextPatch_Set():
return set_(_that);case BridgeAccountTextPatch_Restore():
return restore(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountTextPatch_Keep value)?  keep,TResult? Function( BridgeAccountTextPatch_Set value)?  set_,TResult? Function( BridgeAccountTextPatch_Restore value)?  restore,}){
final _that = this;
switch (_that) {
case BridgeAccountTextPatch_Keep() when keep != null:
return keep(_that);case BridgeAccountTextPatch_Set() when set_ != null:
return set_(_that);case BridgeAccountTextPatch_Restore() when restore != null:
return restore(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  keep,TResult Function( String value)?  set_,TResult Function()?  restore,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountTextPatch_Keep() when keep != null:
return keep();case BridgeAccountTextPatch_Set() when set_ != null:
return set_(_that.value);case BridgeAccountTextPatch_Restore() when restore != null:
return restore();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  keep,required TResult Function( String value)  set_,required TResult Function()  restore,}) {final _that = this;
switch (_that) {
case BridgeAccountTextPatch_Keep():
return keep();case BridgeAccountTextPatch_Set():
return set_(_that.value);case BridgeAccountTextPatch_Restore():
return restore();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  keep,TResult? Function( String value)?  set_,TResult? Function()?  restore,}) {final _that = this;
switch (_that) {
case BridgeAccountTextPatch_Keep() when keep != null:
return keep();case BridgeAccountTextPatch_Set() when set_ != null:
return set_(_that.value);case BridgeAccountTextPatch_Restore() when restore != null:
return restore();case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountTextPatch_Keep extends BridgeAccountTextPatch {
  const BridgeAccountTextPatch_Keep(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTextPatch_Keep);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountTextPatch.keep()';
}


}




/// @nodoc


class BridgeAccountTextPatch_Set extends BridgeAccountTextPatch {
  const BridgeAccountTextPatch_Set({required this.value}): super._();


 final  String value;

/// Create a copy of BridgeAccountTextPatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountTextPatch_SetCopyWith<BridgeAccountTextPatch_Set> get copyWith => _$BridgeAccountTextPatch_SetCopyWithImpl<BridgeAccountTextPatch_Set>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTextPatch_Set&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeAccountTextPatch.set_(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountTextPatch_SetCopyWith<$Res> implements $BridgeAccountTextPatchCopyWith<$Res> {
  factory $BridgeAccountTextPatch_SetCopyWith(BridgeAccountTextPatch_Set value, $Res Function(BridgeAccountTextPatch_Set) _then) = _$BridgeAccountTextPatch_SetCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$BridgeAccountTextPatch_SetCopyWithImpl<$Res>
    implements $BridgeAccountTextPatch_SetCopyWith<$Res> {
  _$BridgeAccountTextPatch_SetCopyWithImpl(this._self, this._then);

  final BridgeAccountTextPatch_Set _self;
  final $Res Function(BridgeAccountTextPatch_Set) _then;

/// Create a copy of BridgeAccountTextPatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeAccountTextPatch_Set(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAccountTextPatch_Restore extends BridgeAccountTextPatch {
  const BridgeAccountTextPatch_Restore(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountTextPatch_Restore);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountTextPatch.restore()';
}


}




/// @nodoc
mixin _$BridgeAccountUsageValue {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountUsageValue);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountUsageValue()';
}


}

/// @nodoc
class $BridgeAccountUsageValueCopyWith<$Res>  {
$BridgeAccountUsageValueCopyWith(BridgeAccountUsageValue _, $Res Function(BridgeAccountUsageValue) __);
}


/// Adds pattern-matching-related methods to [BridgeAccountUsageValue].
extension BridgeAccountUsageValuePatterns on BridgeAccountUsageValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountUsageValue_Balance value)?  balance,TResult Function( BridgeAccountUsageValue_Subscription value)?  subscription,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountUsageValue_Balance() when balance != null:
return balance(_that);case BridgeAccountUsageValue_Subscription() when subscription != null:
return subscription(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountUsageValue_Balance value)  balance,required TResult Function( BridgeAccountUsageValue_Subscription value)  subscription,}){
final _that = this;
switch (_that) {
case BridgeAccountUsageValue_Balance():
return balance(_that);case BridgeAccountUsageValue_Subscription():
return subscription(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountUsageValue_Balance value)?  balance,TResult? Function( BridgeAccountUsageValue_Subscription value)?  subscription,}){
final _that = this;
switch (_that) {
case BridgeAccountUsageValue_Balance() when balance != null:
return balance(_that);case BridgeAccountUsageValue_Subscription() when subscription != null:
return subscription(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool available,  List<BridgeAccountMoneyBalance> balances)?  balance,TResult Function( String? level,  List<BridgeAccountQuota> quotas)?  subscription,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountUsageValue_Balance() when balance != null:
return balance(_that.available,_that.balances);case BridgeAccountUsageValue_Subscription() when subscription != null:
return subscription(_that.level,_that.quotas);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool available,  List<BridgeAccountMoneyBalance> balances)  balance,required TResult Function( String? level,  List<BridgeAccountQuota> quotas)  subscription,}) {final _that = this;
switch (_that) {
case BridgeAccountUsageValue_Balance():
return balance(_that.available,_that.balances);case BridgeAccountUsageValue_Subscription():
return subscription(_that.level,_that.quotas);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool available,  List<BridgeAccountMoneyBalance> balances)?  balance,TResult? Function( String? level,  List<BridgeAccountQuota> quotas)?  subscription,}) {final _that = this;
switch (_that) {
case BridgeAccountUsageValue_Balance() when balance != null:
return balance(_that.available,_that.balances);case BridgeAccountUsageValue_Subscription() when subscription != null:
return subscription(_that.level,_that.quotas);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountUsageValue_Balance extends BridgeAccountUsageValue {
  const BridgeAccountUsageValue_Balance({required this.available, required  List<BridgeAccountMoneyBalance> balances}): _balances = balances,super._();


 final  bool available;
 final  List<BridgeAccountMoneyBalance> _balances;
 List<BridgeAccountMoneyBalance> get balances {
  if (_balances is EqualUnmodifiableListView) return _balances;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_balances);
}


/// Create a copy of BridgeAccountUsageValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountUsageValue_BalanceCopyWith<BridgeAccountUsageValue_Balance> get copyWith => _$BridgeAccountUsageValue_BalanceCopyWithImpl<BridgeAccountUsageValue_Balance>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountUsageValue_Balance&&(identical(other.available, available) || other.available == available)&&const DeepCollectionEquality().equals(other.balances, _balances));
}


@override
int get hashCode {
    return Object.hash(runtimeType,available,const DeepCollectionEquality().hash(_balances));
}

@override
String toString() {
    return 'BridgeAccountUsageValue.balance(available: $available, balances: $balances)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountUsageValue_BalanceCopyWith<$Res> implements $BridgeAccountUsageValueCopyWith<$Res> {
  factory $BridgeAccountUsageValue_BalanceCopyWith(BridgeAccountUsageValue_Balance value, $Res Function(BridgeAccountUsageValue_Balance) _then) = _$BridgeAccountUsageValue_BalanceCopyWithImpl;
@useResult
$Res call({
 bool available, List<BridgeAccountMoneyBalance> balances
});




}
/// @nodoc
class _$BridgeAccountUsageValue_BalanceCopyWithImpl<$Res>
    implements $BridgeAccountUsageValue_BalanceCopyWith<$Res> {
  _$BridgeAccountUsageValue_BalanceCopyWithImpl(this._self, this._then);

  final BridgeAccountUsageValue_Balance _self;
  final $Res Function(BridgeAccountUsageValue_Balance) _then;

/// Create a copy of BridgeAccountUsageValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? available = null,Object? balances = null,}) {
  return _then(BridgeAccountUsageValue_Balance(
available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,balances: null == balances ? _self._balances : balances // ignore: cast_nullable_to_non_nullable
as List<BridgeAccountMoneyBalance>,
  ));
}


}

/// @nodoc


class BridgeAccountUsageValue_Subscription extends BridgeAccountUsageValue {
  const BridgeAccountUsageValue_Subscription({this.level, required  List<BridgeAccountQuota> quotas}): _quotas = quotas,super._();


 final  String? level;
 final  List<BridgeAccountQuota> _quotas;
 List<BridgeAccountQuota> get quotas {
  if (_quotas is EqualUnmodifiableListView) return _quotas;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_quotas);
}


/// Create a copy of BridgeAccountUsageValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountUsageValue_SubscriptionCopyWith<BridgeAccountUsageValue_Subscription> get copyWith => _$BridgeAccountUsageValue_SubscriptionCopyWithImpl<BridgeAccountUsageValue_Subscription>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountUsageValue_Subscription&&(identical(other.level, level) || other.level == level)&&const DeepCollectionEquality().equals(other.quotas, _quotas));
}


@override
int get hashCode {
    return Object.hash(runtimeType,level,const DeepCollectionEquality().hash(_quotas));
}

@override
String toString() {
    return 'BridgeAccountUsageValue.subscription(level: $level, quotas: $quotas)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountUsageValue_SubscriptionCopyWith<$Res> implements $BridgeAccountUsageValueCopyWith<$Res> {
  factory $BridgeAccountUsageValue_SubscriptionCopyWith(BridgeAccountUsageValue_Subscription value, $Res Function(BridgeAccountUsageValue_Subscription) _then) = _$BridgeAccountUsageValue_SubscriptionCopyWithImpl;
@useResult
$Res call({
 String? level, List<BridgeAccountQuota> quotas
});




}
/// @nodoc
class _$BridgeAccountUsageValue_SubscriptionCopyWithImpl<$Res>
    implements $BridgeAccountUsageValue_SubscriptionCopyWith<$Res> {
  _$BridgeAccountUsageValue_SubscriptionCopyWithImpl(this._self, this._then);

  final BridgeAccountUsageValue_Subscription _self;
  final $Res Function(BridgeAccountUsageValue_Subscription) _then;

/// Create a copy of BridgeAccountUsageValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? level = freezed,Object? quotas = null,}) {
  return _then(BridgeAccountUsageValue_Subscription(
level: freezed == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String?,quotas: null == quotas ? _self._quotas : quotas // ignore: cast_nullable_to_non_nullable
as List<BridgeAccountQuota>,
  ));
}


}

/// @nodoc
mixin _$BridgeAutoCompactIntent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAutoCompactIntent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAutoCompactIntent()';
}


}

/// @nodoc
class $BridgeAutoCompactIntentCopyWith<$Res>  {
$BridgeAutoCompactIntentCopyWith(BridgeAutoCompactIntent _, $Res Function(BridgeAutoCompactIntent) __);
}


/// Adds pattern-matching-related methods to [BridgeAutoCompactIntent].
extension BridgeAutoCompactIntentPatterns on BridgeAutoCompactIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAutoCompactIntent_Set value)?  set_,TResult Function( BridgeAutoCompactIntent_Clear value)?  clear,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAutoCompactIntent_Set() when set_ != null:
return set_(_that);case BridgeAutoCompactIntent_Clear() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAutoCompactIntent_Set value)  set_,required TResult Function( BridgeAutoCompactIntent_Clear value)  clear,}){
final _that = this;
switch (_that) {
case BridgeAutoCompactIntent_Set():
return set_(_that);case BridgeAutoCompactIntent_Clear():
return clear(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAutoCompactIntent_Set value)?  set_,TResult? Function( BridgeAutoCompactIntent_Clear value)?  clear,}){
final _that = this;
switch (_that) {
case BridgeAutoCompactIntent_Set() when set_ != null:
return set_(_that);case BridgeAutoCompactIntent_Clear() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt limit)?  set_,TResult Function()?  clear,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAutoCompactIntent_Set() when set_ != null:
return set_(_that.limit);case BridgeAutoCompactIntent_Clear() when clear != null:
return clear();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt limit)  set_,required TResult Function()  clear,}) {final _that = this;
switch (_that) {
case BridgeAutoCompactIntent_Set():
return set_(_that.limit);case BridgeAutoCompactIntent_Clear():
return clear();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt limit)?  set_,TResult? Function()?  clear,}) {final _that = this;
switch (_that) {
case BridgeAutoCompactIntent_Set() when set_ != null:
return set_(_that.limit);case BridgeAutoCompactIntent_Clear() when clear != null:
return clear();case _:
  return null;

}
}

}

/// @nodoc


class BridgeAutoCompactIntent_Set extends BridgeAutoCompactIntent {
  const BridgeAutoCompactIntent_Set({required this.limit}): super._();


 final  BigInt limit;

/// Create a copy of BridgeAutoCompactIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAutoCompactIntent_SetCopyWith<BridgeAutoCompactIntent_Set> get copyWith => _$BridgeAutoCompactIntent_SetCopyWithImpl<BridgeAutoCompactIntent_Set>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAutoCompactIntent_Set&&(identical(other.limit, limit) || other.limit == limit));
}


@override
int get hashCode {
    return Object.hash(runtimeType,limit);
}

@override
String toString() {
    return 'BridgeAutoCompactIntent.set_(limit: $limit)';
}


}

/// @nodoc
abstract mixin class $BridgeAutoCompactIntent_SetCopyWith<$Res> implements $BridgeAutoCompactIntentCopyWith<$Res> {
  factory $BridgeAutoCompactIntent_SetCopyWith(BridgeAutoCompactIntent_Set value, $Res Function(BridgeAutoCompactIntent_Set) _then) = _$BridgeAutoCompactIntent_SetCopyWithImpl;
@useResult
$Res call({
 BigInt limit
});




}
/// @nodoc
class _$BridgeAutoCompactIntent_SetCopyWithImpl<$Res>
    implements $BridgeAutoCompactIntent_SetCopyWith<$Res> {
  _$BridgeAutoCompactIntent_SetCopyWithImpl(this._self, this._then);

  final BridgeAutoCompactIntent_Set _self;
  final $Res Function(BridgeAutoCompactIntent_Set) _then;

/// Create a copy of BridgeAutoCompactIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? limit = null,}) {
  return _then(BridgeAutoCompactIntent_Set(
limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeAutoCompactIntent_Clear extends BridgeAutoCompactIntent {
  const BridgeAutoCompactIntent_Clear(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAutoCompactIntent_Clear);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAutoCompactIntent.clear()';
}


}




/// @nodoc
mixin _$BridgeModelConnectionIntent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModelConnectionIntent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeModelConnectionIntent()';
}


}

/// @nodoc
class $BridgeModelConnectionIntentCopyWith<$Res>  {
$BridgeModelConnectionIntentCopyWith(BridgeModelConnectionIntent _, $Res Function(BridgeModelConnectionIntent) __);
}


/// Adds pattern-matching-related methods to [BridgeModelConnectionIntent].
extension BridgeModelConnectionIntentPatterns on BridgeModelConnectionIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeModelConnectionIntent_Set value)?  set_,TResult Function( BridgeModelConnectionIntent_Clear value)?  clear,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeModelConnectionIntent_Set() when set_ != null:
return set_(_that);case BridgeModelConnectionIntent_Clear() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeModelConnectionIntent_Set value)  set_,required TResult Function( BridgeModelConnectionIntent_Clear value)  clear,}){
final _that = this;
switch (_that) {
case BridgeModelConnectionIntent_Set():
return set_(_that);case BridgeModelConnectionIntent_Clear():
return clear(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeModelConnectionIntent_Set value)?  set_,TResult? Function( BridgeModelConnectionIntent_Clear value)?  clear,}){
final _that = this;
switch (_that) {
case BridgeModelConnectionIntent_Set() when set_ != null:
return set_(_that);case BridgeModelConnectionIntent_Clear() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAccountConnectionMode mode)?  set_,TResult Function()?  clear,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeModelConnectionIntent_Set() when set_ != null:
return set_(_that.mode);case BridgeModelConnectionIntent_Clear() when clear != null:
return clear();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAccountConnectionMode mode)  set_,required TResult Function()  clear,}) {final _that = this;
switch (_that) {
case BridgeModelConnectionIntent_Set():
return set_(_that.mode);case BridgeModelConnectionIntent_Clear():
return clear();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAccountConnectionMode mode)?  set_,TResult? Function()?  clear,}) {final _that = this;
switch (_that) {
case BridgeModelConnectionIntent_Set() when set_ != null:
return set_(_that.mode);case BridgeModelConnectionIntent_Clear() when clear != null:
return clear();case _:
  return null;

}
}

}

/// @nodoc


class BridgeModelConnectionIntent_Set extends BridgeModelConnectionIntent {
  const BridgeModelConnectionIntent_Set({required this.mode}): super._();


 final  BridgeAccountConnectionMode mode;

/// Create a copy of BridgeModelConnectionIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeModelConnectionIntent_SetCopyWith<BridgeModelConnectionIntent_Set> get copyWith => _$BridgeModelConnectionIntent_SetCopyWithImpl<BridgeModelConnectionIntent_Set>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModelConnectionIntent_Set&&(identical(other.mode, mode) || other.mode == mode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,mode);
}

@override
String toString() {
    return 'BridgeModelConnectionIntent.set_(mode: $mode)';
}


}

/// @nodoc
abstract mixin class $BridgeModelConnectionIntent_SetCopyWith<$Res> implements $BridgeModelConnectionIntentCopyWith<$Res> {
  factory $BridgeModelConnectionIntent_SetCopyWith(BridgeModelConnectionIntent_Set value, $Res Function(BridgeModelConnectionIntent_Set) _then) = _$BridgeModelConnectionIntent_SetCopyWithImpl;
@useResult
$Res call({
 BridgeAccountConnectionMode mode
});




}
/// @nodoc
class _$BridgeModelConnectionIntent_SetCopyWithImpl<$Res>
    implements $BridgeModelConnectionIntent_SetCopyWith<$Res> {
  _$BridgeModelConnectionIntent_SetCopyWithImpl(this._self, this._then);

  final BridgeModelConnectionIntent_Set _self;
  final $Res Function(BridgeModelConnectionIntent_Set) _then;

/// Create a copy of BridgeModelConnectionIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? mode = null,}) {
  return _then(BridgeModelConnectionIntent_Set(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as BridgeAccountConnectionMode,
  ));
}


}

/// @nodoc


class BridgeModelConnectionIntent_Clear extends BridgeModelConnectionIntent {
  const BridgeModelConnectionIntent_Clear(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeModelConnectionIntent_Clear);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeModelConnectionIntent.clear()';
}


}




// dart format on
