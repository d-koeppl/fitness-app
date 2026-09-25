// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_heart_rate_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SessionHeartRateOut _$SessionHeartRateOutFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'SessionHeartRateOut',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'average_bpm',
        'date',
        'end_ts',
        'fetched_at',
        'max_bpm',
        'max_hr',
        'min_bpm',
        'resting_hr',
        'sample_count',
        'samples',
        'session_id',
        'start_ts',
        'zone_source',
        'zones',
      ],
    );
    final val = SessionHeartRateOut(
      averageBpm: $checkedConvert('average_bpm', (v) => v as num?),
      date: $checkedConvert('date', (v) => DateTime.parse(v as String)),
      endTs: $checkedConvert(
        'end_ts',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      fetchedAt: $checkedConvert(
        'fetched_at',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      maxBpm: $checkedConvert('max_bpm', (v) => (v as num?)?.toInt()),
      maxHr: $checkedConvert('max_hr', (v) => (v as num?)?.toInt()),
      minBpm: $checkedConvert('min_bpm', (v) => (v as num?)?.toInt()),
      restingHr: $checkedConvert('resting_hr', (v) => (v as num?)?.toInt()),
      sampleCount: $checkedConvert('sample_count', (v) => (v as num).toInt()),
      samples: $checkedConvert(
        'samples',
        (v) => (v as List<dynamic>)
            .map((e) => (e as List<dynamic>).map((e) => e as Object).toList())
            .toList(),
      ),
      sessionId: $checkedConvert('session_id', (v) => v as String),
      startTs: $checkedConvert(
        'start_ts',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      zoneSource: $checkedConvert('zone_source', (v) => v as String?),
      zones: $checkedConvert(
        'zones',
        (v) => (v as List<dynamic>)
            .map((e) => HeartRateZoneOut.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'averageBpm': 'average_bpm',
    'endTs': 'end_ts',
    'fetchedAt': 'fetched_at',
    'maxBpm': 'max_bpm',
    'maxHr': 'max_hr',
    'minBpm': 'min_bpm',
    'restingHr': 'resting_hr',
    'sampleCount': 'sample_count',
    'sessionId': 'session_id',
    'startTs': 'start_ts',
    'zoneSource': 'zone_source',
  },
);

Map<String, dynamic> _$SessionHeartRateOutToJson(
  SessionHeartRateOut instance,
) => <String, dynamic>{
  'average_bpm': instance.averageBpm,
  'date': instance.date.toIso8601String(),
  'end_ts': instance.endTs?.toIso8601String(),
  'fetched_at': instance.fetchedAt?.toIso8601String(),
  'max_bpm': instance.maxBpm,
  'max_hr': instance.maxHr,
  'min_bpm': instance.minBpm,
  'resting_hr': instance.restingHr,
  'sample_count': instance.sampleCount,
  'samples': instance.samples,
  'session_id': instance.sessionId,
  'start_ts': instance.startTs?.toIso8601String(),
  'zone_source': instance.zoneSource,
  'zones': instance.zones.map((e) => e.toJson()).toList(),
};
