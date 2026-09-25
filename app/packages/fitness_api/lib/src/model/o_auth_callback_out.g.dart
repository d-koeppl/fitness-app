// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'o_auth_callback_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OAuthCallbackOut _$OAuthCallbackOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('OAuthCallbackOut', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['scopes', 'status', 'target']);
      final val = OAuthCallbackOut(
        scopes: $checkedConvert('scopes', (v) => v as String),
        status: $checkedConvert('status', (v) => v as String),
        target: $checkedConvert('target', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$OAuthCallbackOutToJson(OAuthCallbackOut instance) =>
    <String, dynamic>{
      'scopes': instance.scopes,
      'status': instance.status,
      'target': instance.target,
    };
