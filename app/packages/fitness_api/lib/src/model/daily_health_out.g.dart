// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_health_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DailyHealthOut _$DailyHealthOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'DailyHealthOut',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'active_zone_minutes',
            'date',
            'hrv_ms',
            'resting_hr',
            'sleep_minutes',
            'steps',
            'vo2max',
            'weight_kg',
          ],
        );
        final val = DailyHealthOut(
          activeZoneMinutes: $checkedConvert(
            'active_zone_minutes',
            (v) => (v as num?)?.toInt(),
          ),
          date: $checkedConvert('date', (v) => DateTime.parse(v as String)),
          hrvMs: $checkedConvert('hrv_ms', (v) => v as num?),
          restingHr: $checkedConvert('resting_hr', (v) => (v as num?)?.toInt()),
          sleepMinutes: $checkedConvert(
            'sleep_minutes',
            (v) => (v as num?)?.toInt(),
          ),
          steps: $checkedConvert('steps', (v) => (v as num?)?.toInt()),
          vo2max: $checkedConvert('vo2max', (v) => v as num?),
          weightKg: $checkedConvert('weight_kg', (v) => v as num?),
        );
        return val;
      },
      fieldKeyMap: const {
        'activeZoneMinutes': 'active_zone_minutes',
        'hrvMs': 'hrv_ms',
        'restingHr': 'resting_hr',
        'sleepMinutes': 'sleep_minutes',
        'weightKg': 'weight_kg',
      },
    );

Map<String, dynamic> _$DailyHealthOutToJson(DailyHealthOut instance) =>
    <String, dynamic>{
      'active_zone_minutes': instance.activeZoneMinutes,
      'date': instance.date.toIso8601String(),
      'hrv_ms': instance.hrvMs,
      'resting_hr': instance.restingHr,
      'sleep_minutes': instance.sleepMinutes,
      'steps': instance.steps,
      'vo2max': instance.vo2max,
      'weight_kg': instance.weightKg,
    };
