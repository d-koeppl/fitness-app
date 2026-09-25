// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_device_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PushDeviceOut _$PushDeviceOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PushDeviceOut', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['platform', 'registered_at']);
      final val = PushDeviceOut(
        platform: $checkedConvert(
          'platform',
          (v) => $enumDecode(
            _$PushDeviceOutPlatformEnumEnumMap,
            v,
            unknownValue: PushDeviceOutPlatformEnum.unknownDefaultOpenApi,
          ),
        ),
        registeredAt: $checkedConvert(
          'registered_at',
          (v) => DateTime.parse(v as String),
        ),
      );
      return val;
    }, fieldKeyMap: const {'registeredAt': 'registered_at'});

Map<String, dynamic> _$PushDeviceOutToJson(PushDeviceOut instance) =>
    <String, dynamic>{
      'platform': _$PushDeviceOutPlatformEnumEnumMap[instance.platform]!,
      'registered_at': instance.registeredAt.toIso8601String(),
    };

const _$PushDeviceOutPlatformEnumEnumMap = {
  PushDeviceOutPlatformEnum.android: 'android',
  PushDeviceOutPlatformEnum.web: 'web',
  PushDeviceOutPlatformEnum.unknownDefaultOpenApi: 'unknown_default_open_api',
};
