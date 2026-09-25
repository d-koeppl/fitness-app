// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_token_in.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PushTokenIn _$PushTokenInFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PushTokenIn', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['token']);
      final val = PushTokenIn(
        token: $checkedConvert('token', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$PushTokenInToJson(PushTokenIn instance) =>
    <String, dynamic>{'token': instance.token};
