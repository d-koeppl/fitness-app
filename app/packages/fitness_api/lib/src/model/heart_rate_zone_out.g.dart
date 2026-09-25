// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'heart_rate_zone_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HeartRateZoneOut _$HeartRateZoneOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('HeartRateZoneOut', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['lower_bpm', 'seconds', 'upper_bpm', 'zone'],
      );
      final val = HeartRateZoneOut(
        lowerBpm: $checkedConvert('lower_bpm', (v) => (v as num?)?.toInt()),
        seconds: $checkedConvert('seconds', (v) => v as num),
        upperBpm: $checkedConvert('upper_bpm', (v) => (v as num?)?.toInt()),
        zone: $checkedConvert('zone', (v) => v as String),
      );
      return val;
    }, fieldKeyMap: const {'lowerBpm': 'lower_bpm', 'upperBpm': 'upper_bpm'});

Map<String, dynamic> _$HeartRateZoneOutToJson(HeartRateZoneOut instance) =>
    <String, dynamic>{
      'lower_bpm': instance.lowerBpm,
      'seconds': instance.seconds,
      'upper_bpm': instance.upperBpm,
      'zone': instance.zone,
    };
