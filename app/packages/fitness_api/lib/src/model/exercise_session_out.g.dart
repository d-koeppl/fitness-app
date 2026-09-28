// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exercise_session_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExerciseSessionOut _$ExerciseSessionOutFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'ExerciseSessionOut',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'active_zone_minutes',
        'average_heart_rate',
        'date',
        'duration_minutes',
        'end_ts',
        'estimated_load',
        'exercise_type',
        'id',
        'match',
        'metrics',
        'ref_id',
        'skipped',
        'source',
        'start_ts',
        'title',
      ],
    );
    final val = ExerciseSessionOut(
      activeZoneMinutes: $checkedConvert(
        'active_zone_minutes',
        (v) => v as num?,
      ),
      averageHeartRate: $checkedConvert('average_heart_rate', (v) => v as num?),
      date: $checkedConvert('date', (v) => DateTime.parse(v as String)),
      durationMinutes: $checkedConvert('duration_minutes', (v) => v as num?),
      endTs: $checkedConvert(
        'end_ts',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      estimatedLoad: $checkedConvert('estimated_load', (v) => v as num?),
      exerciseType: $checkedConvert('exercise_type', (v) => v as String?),
      id: $checkedConvert('id', (v) => v as String),
      match: $checkedConvert(
        'match',
        (v) => v == null ? null : MatchOut.fromJson(v as Map<String, dynamic>),
      ),
      metrics: $checkedConvert(
        'metrics',
        (v) => Map<String, num>.from(v as Map),
      ),
      refId: $checkedConvert('ref_id', (v) => v as String?),
      skipped: $checkedConvert('skipped', (v) => v as bool),
      source_: $checkedConvert('source', (v) => v as String),
      startTs: $checkedConvert(
        'start_ts',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      title: $checkedConvert('title', (v) => v as String?),
    );
    return val;
  },
  fieldKeyMap: const {
    'activeZoneMinutes': 'active_zone_minutes',
    'averageHeartRate': 'average_heart_rate',
    'durationMinutes': 'duration_minutes',
    'endTs': 'end_ts',
    'estimatedLoad': 'estimated_load',
    'exerciseType': 'exercise_type',
    'refId': 'ref_id',
    'source_': 'source',
    'startTs': 'start_ts',
  },
);

Map<String, dynamic> _$ExerciseSessionOutToJson(ExerciseSessionOut instance) =>
    <String, dynamic>{
      'active_zone_minutes': instance.activeZoneMinutes,
      'average_heart_rate': instance.averageHeartRate,
      'date': instance.date.toIso8601String(),
      'duration_minutes': instance.durationMinutes,
      'end_ts': instance.endTs?.toIso8601String(),
      'estimated_load': instance.estimatedLoad,
      'exercise_type': instance.exerciseType,
      'id': instance.id,
      'match': instance.match?.toJson(),
      'metrics': instance.metrics,
      'ref_id': instance.refId,
      'skipped': instance.skipped,
      'source': instance.source_,
      'start_ts': instance.startTs?.toIso8601String(),
      'title': instance.title,
    };
