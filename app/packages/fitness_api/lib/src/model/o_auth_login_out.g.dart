// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'o_auth_login_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OAuthLoginOut _$OAuthLoginOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('OAuthLoginOut', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['url']);
      final val = OAuthLoginOut(
        url: $checkedConvert('url', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$OAuthLoginOutToJson(OAuthLoginOut instance) =>
    <String, dynamic>{'url': instance.url};
