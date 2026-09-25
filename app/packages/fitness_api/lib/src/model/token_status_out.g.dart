// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'token_status_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TokenStatusOut _$TokenStatusOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'TokenStatusOut',
      json,
      ($checkedConvert) {
        $checkKeys(json, requiredKeys: const ['connected']);
        final val = TokenStatusOut(
          accessTokenExpiresAt: $checkedConvert(
            'access_token_expires_at',
            (v) => v == null ? null : DateTime.parse(v as String),
          ),
          connected: $checkedConvert('connected', (v) => v as bool),
          scopes: $checkedConvert('scopes', (v) => v as String?),
          updatedAt: $checkedConvert(
            'updated_at',
            (v) => v == null ? null : DateTime.parse(v as String),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'accessTokenExpiresAt': 'access_token_expires_at',
        'updatedAt': 'updated_at',
      },
    );

Map<String, dynamic> _$TokenStatusOutToJson(
  TokenStatusOut instance,
) => <String, dynamic>{
  'access_token_expires_at': ?instance.accessTokenExpiresAt?.toIso8601String(),
  'connected': instance.connected,
  'scopes': ?instance.scopes,
  'updated_at': ?instance.updatedAt?.toIso8601String(),
};
