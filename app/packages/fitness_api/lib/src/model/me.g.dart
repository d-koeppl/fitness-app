// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'me.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Me _$MeFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Me', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['email', 'uid']);
      final val = Me(
        email: $checkedConvert('email', (v) => v as String),
        uid: $checkedConvert('uid', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$MeToJson(Me instance) => <String, dynamic>{
  'email': instance.email,
  'uid': instance.uid,
};
