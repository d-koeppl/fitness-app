// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_device_in.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PushDeviceIn _$PushDeviceInFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PushDeviceIn', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['platform', 'token']);
      final val = PushDeviceIn(
        platform: $checkedConvert(
          'platform',
          (v) => $enumDecode(
            _$PushDeviceInPlatformEnumEnumMap,
            v,
            unknownValue: PushDeviceInPlatformEnum.unknownDefaultOpenApi,
          ),
        ),
        token: $checkedConvert('token', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$PushDeviceInToJson(PushDeviceIn instance) =>
    <String, dynamic>{
      'platform': _$PushDeviceInPlatformEnumEnumMap[instance.platform]!,
      'token': instance.token,
    };

const _$PushDeviceInPlatformEnumEnumMap = {
  PushDeviceInPlatformEnum.android: 'android',
  PushDeviceInPlatformEnum.web: 'web',
  PushDeviceInPlatformEnum.unknownDefaultOpenApi: 'unknown_default_open_api',
};
