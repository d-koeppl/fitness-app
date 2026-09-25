// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'score_point_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ScorePointOut _$ScorePointOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ScorePointOut', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['date', 'readiness', 'recovery']);
      final val = ScorePointOut(
        date: $checkedConvert('date', (v) => v as String),
        readiness: $checkedConvert('readiness', (v) => (v as num?)?.toInt()),
        recovery: $checkedConvert('recovery', (v) => (v as num?)?.toInt()),
      );
      return val;
    });

Map<String, dynamic> _$ScorePointOutToJson(ScorePointOut instance) =>
    <String, dynamic>{
      'date': instance.date,
      'readiness': instance.readiness,
      'recovery': instance.recovery,
    };
